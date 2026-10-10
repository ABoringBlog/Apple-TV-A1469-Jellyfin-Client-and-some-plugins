#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dispatch/dispatch.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ATV3_LOOPBACK_PORT 49154
#define ATV3_TOKEN_FILE "/var/mobile/Library/Preferences/org.atv3.remoteinput.token"
// Prototype. Loopback-only socket; no network listener on the ATV's LAN IP.
// Send fixed text frames: "ATV3KEY <key> <phase>\\n"; input is further restricted
// to root via a local SSH session (host-side port forwarding).
static void logline(const char*msg) { FILE*f=fopen("/var/tmp/atv3-ir-injector.log","a"); if(f){fprintf(f,"%s\n",msg);fclose(f);} }
static BOOL tokenOK(const char *presented) {
 if(!presented || !*presented)return NO;
 char expected[160]={0};
 FILE *f=fopen(ATV3_TOKEN_FILE,"r");
 if(!f)return NO;
 if(!fgets(expected,sizeof(expected),f)){fclose(f);return NO;}
 fclose(f);
 size_t n=strlen(expected);
 while(n>0 && (expected[n-1]=='\n' || expected[n-1]=='\r' || expected[n-1]==' ' || expected[n-1]=='\t')) expected[--n]=0;
 if(n<32 || n>128)return NO;
 return strcmp(presented,expected)==0;
}
static int keyaction(int key) { switch(key){case 1:case 3:case 4:case 5:case 6:case 7:case 9:case 10:case 11:case 12:return key;default:return 0;} }
static void injectKey(NSNumber*packed) {
 int v=[packed intValue]; int action=(v>>8)&255; int phase=v&255;
 Class evt=objc_getClass("BREvent"),app=objc_getClass("BRApplication");
 if (!evt||!app) {logline("EVENT_CLASS_UNAVAILABLE");return;}
 SEL factory=NSSelectorFromString(@"eventWithAction:value:atTime:originator:");
 SEL shared=NSSelectorFromString(@"sharedApplication");
 SEL post=NSSelectorFromString(@"postEvent:");
 if (![evt respondsToSelector:factory]||![app respondsToSelector:shared]){logline("EVENT_SELECTOR_UNAVAILABLE");return;}
 id application=((id(*)(id,SEL))objc_msgSend)(app,shared);
 if (!application||![application respondsToSelector:post]){logline("EVENT_APP_UNAVAILABLE");return;}
 double now=[[NSProcessInfo processInfo] systemUptime];
 id event=((id(*)(id,SEL,int,int,double,unsigned))objc_msgSend)(evt,factory,action,phase,now,1);
 if (event){((void(*)(id,SEL,id))objc_msgSend)(application,post,event);logline("EVENT_QUEUED");}
}
static id call0(id obj,const char*name) {
 SEL sel=sel_registerName(name);
 return obj && [obj respondsToSelector:sel] ? ((id(*)(id,SEL))objc_msgSend)(obj,sel) : nil;
}
static BOOL isTextController(id obj) {
 Class cls=objc_getClass("BRTextEntryController");
 return cls && obj && [obj isKindOfClass:cls];
}
static BOOL textFocus=NO;
static id activeTextEditor=nil;
static void (*originalPush)(id,SEL,id)=NULL;
static void (*originalPop)(id,SEL)=NULL;
static void hookedPush(id obj,SEL sel,id controller) {
 if(originalPush)originalPush(obj,sel,controller);
 Class textClass=objc_getClass("BRTextEntryController");
 if(textClass && controller && [controller isKindOfClass:textClass]) {textFocus=YES;activeTextEditor=controller;logline("TEXT_ENTRY_PUSH");}
}
static void hookedPop(id obj,SEL sel) {
 if(originalPop)originalPop(obj,sel);
 id top=call0(obj,"peekController");
 Class textClass=objc_getClass("BRTextEntryController");
 textFocus=(textClass && top && [top isKindOfClass:textClass]);
 activeTextEditor=textFocus?top:nil;
 logline(textFocus?"TEXT_ENTRY_POP_STILL_FOCUSED":"TEXT_ENTRY_POP_UNFOCUSED");
}
static void installTextFocusHook(void) {
 Class cls=objc_getClass("BRControllerStack");
 if(!cls){logline("NO_CONTROLLER_STACK");return;}
 Method push=class_getInstanceMethod(cls,sel_registerName("pushController:"));
 Method pop=class_getInstanceMethod(cls,sel_registerName("popController"));
 if(push){originalPush=(void(*)(id,SEL,id))method_setImplementation(push,(IMP)hookedPush);logline("PUSH_HOOK_READY");}
 if(pop){originalPop=(void(*)(id,SEL))method_setImplementation(pop,(IMP)hookedPop);logline("POP_HOOK_READY");}
}
static BOOL probeFocus(void){return textFocus;}
static BOOL applyText(NSString *text) {
 if(!textFocus || !isTextController(activeTextEditor) || ![text isKindOfClass:[NSString class]] || [text length]>512)return NO;
 id editor=call0(activeTextEditor,"editor");
 id field=call0(editor,"textField");
 SEL set=sel_registerName("setString:");
 if(!field || ![field respondsToSelector:set])return NO;
 ((void(*)(id,SEL,id))objc_msgSend)(field,set,text);
 id delegate=call0(field,"delegate");
 if(!delegate)delegate=call0(editor,"textFieldDelegate");
 SEL changed=sel_registerName("textDidChange:");
 if(delegate && [delegate respondsToSelector:changed])((void(*)(id,SEL,id))objc_msgSend)(delegate,changed,field);
 logline("TEXT_UPDATED");return YES;
}

static BOOL submitText(void) {
 if(!textFocus || !isTextController(activeTextEditor)) return NO;
 id editor=activeTextEditor;
 id inner=call0(editor,"editor");
 id field=call0(inner,"textField");
 id delegate=call0(field,"delegate");
 if(!delegate)delegate=call0(inner,"textFieldDelegate");
 if(!delegate)delegate=call0(editor,"textFieldDelegate");
 SEL completed=sel_registerName("textDidEndEditing:");
 if(!field || !delegate || ![delegate respondsToSelector:completed]) {
    logline("SUBMIT_NO_DELEGATE");return NO;
 }
 ((void(*)(id,SEL,id))objc_msgSend)(delegate,completed,field);
 logline("TEXT_SUBMITTED");return YES;
}
static void process(int fd){
 char buf[8192]={0}; ssize_t n=recv(fd,buf,sizeof(buf)-1,0);
 if(n<=0)return;
 if(n>8 && strncmp(buf,"ATV3TEXT ",9)==0){
   char presentedToken[96]={0};char encoded[4096]={0};
   if(sscanf(buf,"ATV3TEXT %95s %4095s",presentedToken,encoded)!=2 || !tokenOK(presentedToken)){(void)send(fd,"ERR\n",4,0);return;}
   NSData *data=[[[NSData alloc]initWithBase64EncodedString:[NSString stringWithUTF8String:encoded] options:0]autorelease];
   NSString *text=[[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding]autorelease];
   if(!text || [text length]>512){(void)send(fd,"ERR\n",4,0);return;}
   __block BOOL ok=NO;
   dispatch_sync(dispatch_get_main_queue(),^{ok=applyText(text);});
   (void)send(fd,ok?"APPLIED\n":"NO_FIELD\n",ok?8:9,0);return;
 }
 if(n>10 && strncmp(buf,"ATV3SUBMIT ",11)==0){
   char presentedSubmit[96]={0};
   if(sscanf(buf,"ATV3SUBMIT %95s",presentedSubmit)!=1 || !tokenOK(presentedSubmit)){(void)send(fd,"ERR\n",4,0);return;}
   __block BOOL done=NO;
   dispatch_sync(dispatch_get_main_queue(),^{done=submitText();});
   (void)send(fd,done?"SUBMITTED\n":"NO_FIELD\n",done?10:9,0);return;
 }
 int key=0,phase=-1;char presented[96]={0};
 if(sscanf(buf,"ATV3FOCUS %95s",presented)==1 && tokenOK(presented)){
    __block BOOL focused=NO;
    dispatch_sync(dispatch_get_main_queue(),^{focused=probeFocus();});
    (void)send(fd,focused?"FOCUS 1\n":"FOCUS 0\n",8,0);
    return;
 }
 memset(presented,0,sizeof(presented));
 if(sscanf(buf,"ATV3KEY %95s %d %d",presented,&key,&phase)!=3 || !tokenOK(presented)||!keyaction(key)||(phase!=0&&phase!=1&&phase!=2)){
  (void)send(fd,"ERR\n",4,0);return;
 }
 NSNumber *packed=[NSNumber numberWithInt:(key<<8)|phase];
 dispatch_async(dispatch_get_main_queue(),^{injectKey(packed);});
 (void)send(fd,"QUEUED\n",7,0);
}
static void startListener(void){
 int s=socket(AF_INET,SOCK_STREAM,0);if(s<0){logline("SOCKET_ERROR");return;}
 int reuse=1;setsockopt(s,SOL_SOCKET,SO_REUSEADDR,&reuse,sizeof(reuse));
 struct sockaddr_in a;memset(&a,0,sizeof(a));a.sin_family=AF_INET;a.sin_port=htons(ATV3_LOOPBACK_PORT);a.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
 if(bind(s,(struct sockaddr*)&a,sizeof(a))!=0||listen(s,5)!=0){logline("LISTEN_ERROR");close(s);return;}
 logline("LISTENING_127.0.0.1_49154");
 while(1){int fd=accept(s,NULL,NULL);if(fd<0)continue;process(fd);close(fd);}
}
__attribute__((constructor))static void init(void){
 logline("INJECTOR_LOADED");
 dispatch_async(dispatch_get_main_queue(),^{installTextFocusHook();});
 dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND,0),^{startListener();});
}
