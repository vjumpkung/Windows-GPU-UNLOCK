"""Validate the three private Z690 captures and derive host-only fixtures.

No profile generation, hardware access or change to the generic proven envelope.
GPL-2.0-only.
"""
import hashlib
import importlib.util
import json
import re
import struct
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('fingerprint', Path(__file__).with_name('fingerprint_probe.py'))
fingerprint = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fingerprint)
profile = fingerprint._profile
LOCAL = REPO / 'research/profile/local/z690ud-3060'
PROM = '444fd597a205115b6db796245605f58913d5018f61611e08582590f6fd6918a4'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def require(ok, message):
    if not ok:
        raise ValueError(message)


def main():
    inputs, previous, latest = [], None, None
    for number in range(1, 4):
        folder = LOCAL / f'observe-boot{number}'
        sums = (folder / 'SHA256SUMS.txt').read_text().splitlines()
        require(len(sums) >= 42, 'incomplete capture checksum inventory')
        for row in sums:
            match = re.fullmatch(r'([0-9a-f]{64})  ([A-Za-z0-9_.-]+)', row)
            require(match is not None, 'invalid capture checksum row')
            path = folder / match[2]
            require(sha(path.read_bytes()) == match[1], f'capture checksum mismatch: {path.name}')
            inputs.append({'Path': path.relative_to(REPO).as_posix(), 'Sha256': match[1]})
        checksum_path = folder / 'SHA256SUMS.txt'
        inputs.append({'Path': checksum_path.relative_to(REPO).as_posix(), 'Sha256': sha(checksum_path.read_bytes())})
        diag = folder / 'DIAG00.TXT'
        summary = fingerprint.parse(diag)
        expected = {'capture_complete': True, 'probe_status': '0000000000000000',
                    'result': '0000000000000000', 'board_id': '250410de',
                    'subsystem': '00000000153610de', 'bar0': '0000000053000000',
                    'chip': 'b76000a1', 'memory_mib': '3000', 'prom_sha256': PROM,
                    'bdf': '0000:01:00.0', 'gops': '0001', 'missing_mmio': [],
                    'cold': {'plm': 'ffffff8f', 'gfw': '8b8f/3ff/10', 'wpr2_hi': '0', 'ss0': '71010104', 'ss1': '2'}}
        require(all(summary.get(k) == v for k, v in expected.items()), 'capture does not describe the exact Z690 cold profile')
        text = diag.read_text().replace('\r\n', '\n')
        config = re.findall(r'^cfg dwords=(.*)$', text, re.M)
        require(len(config) == 1, 'ambiguous PCI config')
        words = config[0].split()
        require(len(words) == 64, 'missing PCI dwords')
        blocks = profile.parse_handles(text)
        gpu = [h for h, b in blocks.items() if (cfg := profile.pci_config(b['raw'])) and cfg[2] >> 24 == 3]
        require(len(gpu) == 1, 'expected one display controller and no iGPU')
        target = gpu[0]
        children = [e for e in blocks[target]['edges'] if e[0] == '09576e91-6d3f-11d2-8e39-00a0c969723b' and e[3] == 8]
        require(len(children) == 1, 'expected exactly one NVIDIA display child')
        child = children[0][2]
        path = profile.path_of(blocks[child]['raw'])
        require(path == bytes.fromhex('02010c00d041030a0000000001010600000101010600000002030800200301807fff0400'), 'unexpected display path')
        bindings = profile.parse_bindings(text.splitlines())
        for protocol, size, stop in [(profile.TEXT_OUT, 0x5de0, 0xf90), (profile.GOP, 0x3c20, 0xb60)]:
            binding = profile.binding_for(bindings, profile.sole_driver(blocks, child, protocol))
            require(binding['size'] == size and binding['stop'] - binding['base'] == stop and binding['version'] == 0x10, 'console binding fingerprint mismatch')
        images = {}
        for name, handle, protocol, size, stop, version, text_hash in [
            ('edid', child, profile.EDID_DISCOVERED, 0x9000, 0x14d4, 1, '49fe68461765963d0b63144b0a7863f3b2db5926f1c988cbacc1e85ebe2b96f4'),
            ('nvgop', target, profile.PCI_IO, 0x26ae0, 0x678, 0x60010, '615b37a708b1894e18d7fa60cfcdacaa4d8b598863a10b8103d231a595847b2b'),
        ]:
            binding = profile.binding_for(bindings, profile.sole_driver(blocks, handle, protocol))
            require(binding['size'] == size and binding['stop'] - binding['base'] == stop and binding['version'] == version, 'unexpected bound driver')
            data = (folder / f'IMG{binding["dump"]:02d}.BIN').read_bytes()
            at, count = fingerprint.text_section(data)
            require(len(data) == size and sha(data[at:at + count]) == text_hash, 'driver image fingerprint mismatch')
            images[name] = data
        # Relocations make full image hashes differ; compare authenticated .text,
        # sizes and stop offsets above, and complete PCI/path bytes here.
        comparable = (words, path)
        require(previous is None or previous == comparable, 'capture PCI/path disagreement')
        previous, latest = comparable, (folder, words, images)
        require(sha((folder / 'PROM.BIN').read_bytes()) == PROM, 'PROM mismatch')
    folder, words, images = latest
    output = LOCAL / 'fixtures'
    output.mkdir(exist_ok=True)
    cold_line = 'cold state: chip=0xb76000a1 plm=0xffffff8f gfw=0x8b8f/0x3ff/0x10 WPR2_HI=0 SS0=0x71010104 SS1=0x2'
    files = {
        'probe.txt': ''.join(f'config_offset=0x{i * 4:x}\nvalue=0x{w}\n' for i, w in enumerate(words)).encode(),
        'cold.txt': (''.join(f'config[{i * 4:x}]={" ".join(words[i:i + 4])}\n' for i in range(0, 64, 4)) + cold_line + '\nobserved memory=0x3000\n').encode(),
        'config.bin': struct.pack('<64I', *(int(w, 16) for w in words)),
        'PROM.BIN': (folder / 'PROM.BIN').read_bytes(),
        'edid.bin': images['edid'], 'nvgop.bin': images['nvgop'],
    }
    fixtures = []
    for name, data in files.items():
        dest = output / name
        dest.write_bytes(data)
        fixtures.append({'Path': dest.relative_to(REPO).as_posix(), 'Sha256': sha(data)})
    (LOCAL / 'fixture-manifest.json').write_text(json.dumps({'CaptureInputs': inputs, 'FixtureInputs': fixtures}, indent=2) + '\n')
    print('PASS three exact cold captures, checksums, PCI/path, owned driver code and PROM; host fixtures ready')


if __name__ == '__main__':
    main()
