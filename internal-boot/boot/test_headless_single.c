/* GPL-2.0-only. One-child/no-iGPU exact-capture replay, host RAM only. */
#define GU_SINGLE_DISPLAY_CHILD_TEST
#include "test_full.c"

/* Probe IMGxx.BIN files are already mapped images. Do not re-map their raw
 * section offsets as LoadMapped does for the original on-disk PE fixtures. */
static VOID LoadCapturedMapped(const char *path,UINT8 *memory,UINTN size) {
  FILE *f=fopen(path,"rb");Check(f!=NULL,"captured mapped image exists");
  Check(fseek(f,0,SEEK_END)==0 && ftell(f)==(long)size,"exact captured image size");
  rewind(f);Check(fread(memory,1,size,f)==size && fgetc(f)==EOF,"read complete mapped image");fclose(f);
  Check(size>=64 && memory[0]=='M' && memory[1]=='Z',"mapped DOS header present");
  UINT32 pe=0;memcpy(&pe,memory+0x3c,sizeof(pe));
  Check(pe<=size && size-pe>=24 && !memcmp(memory+pe,"PE\0\0",4),"bounded mapped PE header");
  UINT16 optional=0;memcpy(&optional,memory+pe+20,sizeof(optional));
  Check(optional>=60 && optional<=size-pe-24,"bounded mapped optional header");
  UINT32 imageSize=0;memcpy(&imageSize,memory+pe+24+56,sizeof(imageSize));
  Check(imageSize==size,"PE mapped size matches captured extent");
}
static VOID LoadExact(const char *path,VOID *memory,UINTN size) {
  FILE *f=fopen(path,"rb");Check(f!=NULL,"capture fixture exists");
  Check(fread(memory,1,size,f)==size && fgetc(f)==EOF,"exact capture fixture length");fclose(f);
}
int main(int argc,char **argv) {
  Check(argc==5,"mapped EDID image, mapped nvgop image, PROM and full PCI fixture required");
  Check(!FX_Amd && !FX_AmdPci,"capture contains no invented iGPU handles");
  LoadCapturedMapped(argv[1],MouseMemory,sizeof(MouseMemory));
  LoadCapturedMapped(argv[2],NvMemory,sizeof(NvMemory));
  LoadExact(argv[3],PromMemory,sizeof(PromMemory));
  LoadExact(argv[4],InitialFullConfig,sizeof(InitialFullConfig));
  Check(GuHashMatches(PromMemory,sizeof(PromMemory),GU_PROM_SHA256),"captured PROM source pin");
  Check(Bytes(InitialFullConfig,FixtureRtxConfig,sizeof(FixtureRtxConfig)),"same capture's PCI snapshot");
  DecodeTests();
  Check(Run(31)!=EFI_SUCCESS && !Calls,"missing input Reset blocks first detach");
  Check(RunFull(0)==EFI_SUCCESS && Calls==4 && Full.ChildCount==1 && Full.EdidDetached==1 && EnableCalls==1 && ClaimCalls==1 && CloseCalls==1,"two console stops, one EDID stop, NV stop, bounded decode restore and cleanup");
  Check(!Full.Owned && Bytes(MockConfig,InitialFullConfig,sizeof(MockConfig)) && MockAttributes==0x300,"exclusive claim closed and config/cache restored exactly");
  Check(Live.Count+6==sizeof(FixtureEdges)/sizeof(FixtureEdges[0]),"only three console, one EDID and two NV ownership records removed");
  Check(GuVerifyReleased(LastTable,TRUE)==EFI_SUCCESS,"live zero-GOP cold verifier succeeds");
  for(int scenario=1;scenario<=20;scenario++) {
    Check(RunFull(scenario)!=EFI_SUCCESS,"release/config/cold/PROM/code/graph/claim/log fault fails closed");
    if(scenario>=8 && scenario<=13)Check(EnableCalls==1,"failure after decode effect remains failure");
    else Check(!EnableCalls,"prerelease or prewrite failure cannot enable decode");
    if(scenario==18)Check(!ClaimCalls,"late new owner blocks exclusive claim");
    if(scenario==19)Check(Calls==3,"late extra child blocks NV stop");
    if(ClaimCalls==1 && scenario!=4 && scenario!=13)Check(CloseCalls==1 && !Full.Owned,"failed session closes its exclusive claim");
  }
  for(int scenario=23;scenario<=30;scenario++) {
    Check(RunFull(scenario)!=EFI_SUCCESS && !EnableCalls && !ClaimCalls,"extra child/consumer/path/code/missing EDID/warning/partial stop blocks decode");
    if(scenario==23)Check(Calls==2,"unexpected display child rejected before EDID stop");
    if(scenario==25 || scenario==26)Check(Calls==3,"late display path or NV code change blocks NV stop");
    if(scenario==30)Check(Calls==4 && !Full.Released,"partial NV cleanup cannot become release success");
  }
  for(int scenario=32;scenario<=34;scenario++) {
    Check(RunFull(scenario)!=EFI_SUCCESS && !EnableCalls && !ClaimCalls,"live GOP/cold/PROM prerequisite fault blocks decode");
    Check(Calls==(scenario==32?3:2),"prerequisite fault stops before next detach");
  }
  Check(RunFull(0)==EFI_SUCCESS,"new session for late protected graph drift");
  Live.Edges[0].Count++;
  Check(GuVerifyReleased(LastTable,TRUE)!=EFI_SUCCESS,"protected ownership graph remains live after release");
  Check(!strcmp(GuLastVerifyDiagnostic()->Stage,"verify-driver-graph-match"),"protected graph failure identifies its gate");
  Check(RunFull(0)==EFI_SUCCESS,"new session for physical GOP reappearance");
  Phase=3;Check(GuVerifyReleased(LastTable,FALSE)!=EFI_SUCCESS,"reappeared physical GOP blocks handoff");Phase=4;
  Check(RunFull(0)==EFI_SUCCESS,"new session for late input mutation");
  Keys.WaitForKey=NULL;Check(GuVerifyReleased(LastTable,FALSE)!=EFI_SUCCESS,"late input protocol drift blocks handoff");
  Check(RunFull(0)==EFI_SUCCESS,"new session for final PCI mismatch diagnosis");
  MockConfig[16]^=0x100;
  Check(GuVerifyReleased(LastTable,FALSE)==EFI_NOT_READY,"late PCI state drift blocks handoff");
  const GU_VERIFY_DIAGNOSTIC *d=GuLastVerifyDiagnostic();
  Check(d->ConfigDiff && d->Offset==64 && d->Expected==InitialFullConfig[16] && d->Observed==MockConfig[16],"exact PCI mismatch preserved");
  Check(RunFull(0)==EFI_SUCCESS,"new session for post-unlock status policy");
  MockConfig[32]&=~0x90000U;
  Check(GuVerifyReleased(LastTable,FALSE)==EFI_SUCCESS,"only previously observed CED/URD clearing allowed after unlock");
  Check(GuVerifyReleased(LastTable,TRUE)!=EFI_SUCCESS,"same status change blocked before unlock");
  MockConfig[1]|=4;Check(GuVerifyReleased(LastTable,FALSE)!=EFI_SUCCESS,"BME drift blocks handoff");
  printf("PASS single-child headless release checks: %d; captured graph/code/PROM, no GPU or firmware access\n",Checks);
  return 0;
}
