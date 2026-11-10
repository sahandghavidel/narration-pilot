#!/usr/bin/env node
// One Node/AgentCursor process for repeated, already-authored guided scenes.
// The app alone accepts the real user's approvals; this process never sends A/G.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {randomUUID, createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {execFile, execFileSync} from 'node:child_process';
import {promisify} from 'node:util';
import {createRequire} from 'node:module';
const exec = promisify(execFile), repo=path.resolve(import.meta.dirname,'..');
const flags=Object.fromEntries(process.argv.slice(2).reduce((a,v,i,all)=>i%2===0?[...a,[v.replace(/^--/,''),all[i+1]]]:a,[]));
const root=path.resolve(flags.directory??path.join(os.homedir(),'Library/Application Support/local.clipboardreadermac/GuidedSessionRunner'));
const appRoot=path.resolve(flags['app-directory']??path.join(os.homedir(),'Library/Application Support/local.clipboardreadermac'));
const sdkPath=path.resolve(flags.sdk??'/Users/sahand/Documents/Codex/2026-10-31/youtube-to-tested-tutorial/work/agentcursor/dist/lib.js');
const sdk=await import(pathToFileURL(sdkPath).href);
for(const d of ['','commands','receipts','events','scenes'])fs.mkdirSync(path.join(root,d),{recursive:true,mode:0o700});
const read=p=>JSON.parse(fs.readFileSync(p,'utf8'));
const atomic=(p,v)=>{const tmp=p+'.'+randomUUID()+'.tmp';fs.writeFileSync(tmp,JSON.stringify(v,null,2),{mode:0o600});fs.renameSync(tmp,p)};
const stable=v=>JSON.stringify(v,(_,value)=>value&&typeof value==='object'&&!Array.isArray(value)?Object.fromEntries(Object.entries(value).sort(([a],[b])=>a.localeCompare(b))):value);
const hash=v=>createHash('sha256').update(stable(v)).digest('hex');
const sameID=(a,b)=>String(a??'').toLowerCase()===String(b??'').toLowerCase();
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const utc=()=>new Date().toISOString().replace(/\.\d{3}Z$/,'Z');
let lastChapterRequest=null;
let stopped=false,job=null,scene=null,desktop=null,evidence=null,sequence=0,lastReadApp=null,nativeCapture=flags.visual!=='supplied';
let state={schemaVersion:1,pid:process.pid,running:true,phase:'idle',message:'Runner ready for a prepared scene.',sequence};
function publish(patch={}){state={...state,...patch,updatedAt:new Date().toISOString()};atomic(path.join(root,'status.json'),state)}
function emit(kind,data={}){const event={id:randomUUID(),sequence:++sequence,kind,createdAt:new Date().toISOString(),...data};atomic(path.join(root,'events',`${String(sequence).padStart(8,'0')}-${event.id}.json`),event);publish({sequence,lastEvent:event});return event}
function attention(message){
 publish({phase:'needsAgent',reason:'workflowFailure',message});
 emit('needsAgent',{message,sessionID:scene?.config.sessionID,runID:scene?.boundRun});
}
function fresh(p){const data=read(p);if(Date.now()-fs.statSync(p).mtimeMs>4000||data.appRunning===false)throw Error('App feedback is stale; do not perform screen actions.');return data}
const guide=()=>fresh(path.join(appRoot,'GuidedNarrationReview/status.json'));
const practice=()=>fresh(path.join(appRoot,'GuidedNarrationReview/Practice/status.json'));
const feedback=()=>fresh(path.join(appRoot,'AgentFeedback/status.json'));
function paused(){const f=feedback();if(f.focuSee?.observedState!=='paused'||Date.now()-Date.parse(f.focuSee.observedAt)>2000)throw Error('FocuSee must be freshly observed paused.');return f}
function valid(run){const p=practice();if(stopped||['blocked','suspended','inactive'].includes(p.phase))throw Error('CANCELLED: workflow stopped or suspended');if(!sameID(p.runID,run)||!sameID(p.approval?.draft?.sessionID,scene.config.sessionID)||!p.active)throw Error('CANCELLED: guided attempt changed');return p}
async function appCommand(kind,payload={}){
 const p=practice(),id=randomUUID(),file=path.join(appRoot,'GuidedNarrationReview/Practice/commands',id+'.json');
 atomic(file,{schemaVersion:1,id,createdAt:utc(),sessionID:p.approval.draft.sessionID,runID:p.runID,kind,...payload});
 const until=Date.now()+15000,receipt=file.replace('/commands/','/receipts/');
 while(Date.now()<until){if(fs.existsSync(receipt)){const r=read(receipt);if(!r.accepted)throw Error(r.message);return r}await sleep(20)}
 throw Error('Command receipt timed out; inspect status before retrying.');
}
function normalize(view){return {app:{name:view.app.name,bundleId:view.app.bundleId},window:view.window,elements:view.elements.map(({ref,...e})=>({...e,...(e.role==='radio'&&view.app.bundleId==='com.google.Chrome'?{name:e.name.replace(/ - Memory usage - [\d.,]+ [KMGT]?B$/,'')}:{})}))}}
class SessionPersona extends sdk.Persona {
 thinkTimeMs(n){return Math.round(super.thinkTimeMs(n)*(scene?.config.pacing?.reaction??1))}
 traits(){const t=super.traits();return{...t,speedFactor:t.speedFactor*(scene?.config.pacing?.speed??1),dwellScale:t.dwellScale*(scene?.config.pacing?.dwell??1)}}
}
async function connect(){desktop?.close();lastReadApp=null;desktop=new sdk.Desktop(new sdk.DesktopService(new SessionPersona({seed:scene.config.seed??4103}),{background:false,showCursor:false}));}
async function activate(app){const result=await desktop.activate(scene?.config.appLaunchNames?.[app]??app);if(!result.active)throw Error('Could not activate '+app);lastReadApp=app;return result}
async function minimizeCodex(){
 const app=(await desktop.apps()).find(a=>a.bundleId==='com.openai.codex');
 if(app?.active){const activated=await desktop.activate(app.name);if(!activated.active||activated.bundleId!=='com.openai.codex')throw Error('Could not select Codex for minimization');await desktop.key('cmd+m');lastReadApp=null;}
}
async function observe(){const views={};for(const app of scene.config.observeApps){views[app]=normalize(await desktop.view({app,max:scene.config.maxElements??200}));lastReadApp=app;}return {views,cursor:await desktop.actions.cursor()}}
function comparableSnapshot(snapshot){
 const copy=structuredClone(snapshot);
 for(const view of Object.values(copy.views)){
  if(view.app.bundleId==='com.microsoft.VSCode' && scene?.config.cosmeticCodeTabMetadata){
   view.window.title=view.window.title.replace(/ — Modified$/,'');
   for(const el of view.elements)if(el.role==='radio'||el.role==='textarea')el.name=el.name?.replace(/, preview$/,'');
   for(const el of view.elements)if(el.role==='button'&&/^Go (Back|Forward) \(/.test(el.name??''))delete el.enabled;
  }
  if(view.app.bundleId==='com.apple.finder'){
   for(const el of view.elements){
    if(el.role==='text')el.name=el.name?.replace(/( selected, )([\d.,]+ [KMGT]B)( available)$/,'$1…$3');
   }
  }
  // Explicitly reviewed elapsed-time labels may change while all meaningful UI stays fixed.
  for(const region of scene?.config.cosmeticElapsedLabels??[]){
   if(view.app.name!==region.app)continue;
   const [x,y,width,height]=region.rect;
   for(const el of view.elements){
    const r=el.rect,cx=r?.x+r?.width/2,cy=r?.y+r?.height/2;
    if(el.role==='text' && /^(?:now|\d+\s*(?:s|min|h|d|sec|hour|day)s?)$/.test(el.name??'') && cx>=x && cx<=x+width && cy>=y && cy<=y+height){
     el.name='<reviewed elapsed time>';el.rect={x,y,width,height};
    }
   }
  }
  if(view.app.bundleId!=='com.google.Chrome')continue;
  for(const el of view.elements){
   // Chrome sometimes omits the unchecked value after dismissing Downloads.
   if(el.role==='checkbox' && el.name==='Downloads - pinned' && el.value==='0')delete el.value;
  }
 }
 return copy;
}
function assertSnapshot(current,baseline){
 const actual=comparableSnapshot(current), expected=comparableSnapshot(baseline);
 const tolerance=Math.min(2,Math.max(0,scene?.config.axRectTolerance??0));
 if(tolerance)for(const [app,before] of Object.entries(expected.views)){
  const after=actual.views[app];if(!after||before.elements.length!==after.elements.length)continue;
  before.elements.forEach((el,i)=>{const other=after.elements[i];const {rect:a,...restA}=el,{rect:b,...restB}=other;
   if(stable(restA)===stable(restB)&&a&&b&&Object.keys(a).every(k=>Number.isFinite(a[k])&&Number.isFinite(b[k])&&Math.abs(a[k]-b[k])<=tolerance))other.rect=structuredClone(a);
  });
 }
 if(stable(actual)===stable(expected))return;
 for(const [app,before] of Object.entries(expected.views)){
  const after=actual.views[app];
  if(!after || before.window.title!==after.window.title)throw Error(app+' starting window changed. Expected “'+before.window.title+'”, found “'+(after?.window.title??'no window')+'”.');
  if(stable(before.window)!==stable(after.window))throw Error(app+' window position or size changed.');
  const index=before.elements.findIndex((element,i)=>stable(element)!==stable(after.elements[i]));
  if(index>=0 || before.elements.length!==after.elements.length){
   const i=index>=0?index:before.elements.length, prev=before.elements[i], next=after.elements[i];
   const property=Object.keys({...prev,...next}).find(key=>stable(prev?.[key])!==stable(next?.[key]));
   throw Error(app+' starting screen changed: '+(prev?.role??next?.role??'control')+' '+(property??'presence')+' differs at item '+(i+1)+'.');
  }
 }
 if(stable(actual.cursor)!==stable(expected.cursor))throw Error('Cursor has not returned to the practiced starting position.');
 throw Error('Observed app or window differs from the practiced starting screen.');
}
function validateAction(a){
 if(a.systemOverlay && (!['move','click','highlight'].includes(a.verb)||![a.target?.x,a.target?.y].every(Number.isFinite)))throw Error('System overlays require a coordinate pointer action.');
 if(['highlight','previewDrag'].includes(a.verb) && ![a.target?.x,a.target?.y,a.end?.x,a.end?.y].every(Number.isFinite))throw Error('Highlight requires visible text start and end coordinates.');
 if(a.target?.x!==undefined&&(!Number.isFinite(a.target.x)||!Number.isFinite(a.target.y)))throw Error('Coordinate targets must be finite');if(!a.id||!['click','doubleClick','move','highlight','previewDrag','type','key','scroll','activate','hold'].includes(a.verb)||a.practiceSafe!==true)throw Error('Every action must have an ID, supported verb, and explicit practiceSafe:true.');if(a.verb==='type'&&a.submit)throw Error('Submit actions require separate agent handling; they cannot be rehearsed automatically.');}
async function target(a){if(a.target?.x!==undefined)return a.target;if(!a.target?.name)throw Error('Action target is missing');const app=a.app??scene.config.startingApp;const v=await desktop.view({app,max:scene.config.maxElements??200});lastReadApp=app;const found=v.elements.filter(e=>e.name===a.target.name&&(!a.target.role||e.role===a.target.role));if(found.length!==1)throw Error('Target must match exactly one visible element: '+a.target.name);const e=found[0];return {x:e.rect.x+e.rect.width/2,y:e.rect.y+e.rect.height/2};}
async function perform(a){
 if(a.whenFileTextEquals && fs.readFileSync(a.whenFileTextEquals.path,"utf8")!==a.whenFileTextEquals.text)return;
 if(a.verb==='activate'){await activate(a.app);return}
 const app=a.app??scene.config.startingApp;
 if(a.systemOverlay){
  // Target the visible system menu or panel without raising its underlying browser.
  const pointer=new sdk.DesktopService(new SessionPersona({seed:scene.config.seed??4103}),{background:false,showCursor:false});
  try{await performPointer(pointer,a,a.target)}finally{pointer.close()}
  return;
 }
 if(lastReadApp!==app){await desktop.view({app,max:scene.config.maxElements??200});lastReadApp=app;}
 if(['click','doubleClick','move','highlight','previewDrag'].includes(a.verb))await performPointer(desktop,a,scene.targets?.[a.id]??await target(a));
 else if(a.verb==='type'){if(a.paste){execFileSync('/usr/bin/pbcopy',{input:a.text});await desktop.key('cmd+v')}else await desktop.type(a.text,{submit:false});}
 else if(a.verb==='key')await desktop.key(a.key);
 else if(a.verb==='scroll')await desktop.scroll({...a.scroll,style:'trackpad'});
}
async function performPointer(pointer,a,start){
 if(a.verb==='click')await pointer.click(start);
 else if(a.verb==='doubleClick')await pointer.dblclick(start);
 else if(a.verb==='move')await pointer.move(start);
 else if(a.verb==='previewDrag'){
  // Use AgentCursor's installed mouse backend to hold through Escape.
  const backendPath=createRequire(sdkPath).resolve('@nut-tree-fork/nut-js');
  const {mouse,Button}=await import(pathToFileURL(backendPath).href);
  await pointer.move(start);
  await mouse.pressButton(Button.LEFT);
  try{
   await sleep(150);
   await pointer.move(a.end);
   await pointer.key('escape');
  }catch(error){
   await pointer.move(start);
   throw error;
  }finally{await mouse.releaseButton(Button.LEFT)}
 }
 else{
  await pointer.drag(start,a.end,{durationMs:350});
  await pointer.move({x:a.end.x+8,y:a.end.y+1});
 }
}
async function images(label){
 const apps=scene.config.observeApps,files={};
 if(nativeCapture){try{for(const app of apps){const file=path.join(scene.dir,`${label}-${hash(app).slice(0,8)}.jpg`);await desktop.screenshot({app,path:file,maxWidth:4096});fs.chmodSync(file,0o600);files[app]=file;}return files}catch(error){nativeCapture=false;emit('captureUnavailable',{message:'Use fresh CUA images; no permission bypass or installation.',detail:error.message.slice(0,180)})}}
 const id=randomUUID(),requestedAt=Date.now();publish({phase:'needsEvidence',message:'Fresh window images are needed from the active agent.',evidenceRequest:{id,apps,label,requestedAt:new Date(requestedAt).toISOString(),directory:scene.dir}});emit('needsEvidence',{requestID:id,apps,label});
 const manifest=await new Promise((resolve,reject)=>{evidence={id,requestedAt,resolve,reject}});evidence=null;
 for(const app of apps){const from=manifest.images?.[app];if(!from||!path.isAbsolute(from)||fs.statSync(from).mtimeMs<requestedAt-1000)throw Error('Evidence is missing or predates the request');const file=path.join(scene.dir,`${label}-${hash(app).slice(0,8)}${path.extname(from)}`);fs.copyFileSync(from,file);fs.chmodSync(file,0o600);files[app]=file;}
 if(Date.now()-Date.parse(manifest.capturedAt)>30000)throw Error('Image evidence is stale');publish({phase:'verifyingEvidence',evidenceRequest:null});return files;
}
async function compareImages(baseline,current){const file=path.join(scene.dir,'image-comparison-input.json');atomic(file,{baseline,current,masks:scene.config.cosmeticMasks??{},visualTolerance:scene.config.visualTolerance??{}});const {stdout}=await exec('python3',[path.join(repo,'scripts/guided-continuity.py'),file]);const result=JSON.parse(stdout);if(!result.matched)throw Error('Visual continuity mismatch: '+JSON.stringify(result));return result;}
async function bindTargets(){scene.targets={};for(const a of [...scene.config.actions,...(scene.config.restoreActions??[])])if(a.target&&!a.deferred)scene.targets[a.id]=await target(a);}
async function restore(run,label){
 paused();await connect();await minimizeCodex();
 for(const a of scene.config.restoreActions??[]){if(a.whenWindowTitleExcludes){const v=await desktop.view({app:a.app??scene.config.startingApp,max:scene.config.maxElements??200});lastReadApp=a.app??scene.config.startingApp;if(v.window.title.includes(a.whenWindowTitleExcludes))continue}await perform(a);if(a.settleMilliseconds)await sleep(Math.min(2000,Math.max(0,a.settleMilliseconds)));}
 await activate(scene.config.startingApp);
 for(let n=0;n<4;n++){await desktop.move({x:scene.baseline.cursor.x+.5,y:scene.baseline.cursor.y+.5});const p=await desktop.actions.cursor();if(stable(p)===stable(scene.baseline.cursor))break}
 assertSnapshot(await observe(),scene.baseline.snapshot);
 const shots=await images(label);valid(run);assertSnapshot(await observe(),scene.baseline.snapshot);paused();
 await bindTargets();await activate(scene.config.startingApp);
 const comparison=await compareImages(scene.baseline.images,shots),evidencePath=path.join(scene.dir,label+'-gate-evidence.json');
 atomic(evidencePath,{checkpointID:scene.baseline.checkpointID,matched:true,comparison,snapshot:scene.baseline.snapshot,images:shots});
 return {checkpointID:scene.baseline.checkpointID,verifiedAt:utc(),matched:true,evidencePath};
}
function resolvePlan(context){
 const clean=w=>w.toLowerCase().replace(/[^\p{L}\p{N}]/gu,'');
 const actions=scene.config.actions.map(a=>{let seconds=a.atSeconds;if(a.cue){const aliases=(a.cue.words??[a.cue.word]).map(clean),hits=context.words.map((w,i)=>aliases.includes(clean(w.word))?i:-1).filter(i=>i>=0);const index=hits[(a.cue.occurrence??1)-1];if(index===undefined)throw Error('Word cue not found: '+JSON.stringify(a.cue));seconds=Math.max(0,context.words[index].start-(a.cue.leadSeconds??0));}if(!Number.isFinite(seconds)||seconds<0||seconds>context.duration)throw Error('Action anchor is outside the approved audio');return {id:a.id,description:a.description??a.id,atSeconds:seconds}});
 return {id:randomUUID(),audioVersionID:context.audioVersionID,audioSHA256:context.audioSHA256,checkpointID:scene.baseline.checkpointID,actions};
}
async function execute(run,mode,plan){
 const until=Date.now()+15000;let started=false;
 while(Date.now()<until){const p=valid(run),f=feedback();if(['blocked','suspended','inactive'].includes(p.phase))throw Error('Workflow interrupted');
  if(mode==='practice'&&p.phase==='practicing'&&p.elapsed>0&&f.focuSee.observedState==='paused'){started=true;break}
  if(mode==='record'&&p.phase==='recording'){const file=path.join(appRoot,'Runtime/approved-audio-recording.json');if(!fs.existsSync(file)||Date.now()-fs.statSync(file).mtimeMs>4000){await sleep(10);continue}const r=fresh(file);if(r.busy&&r.phase==='playing'&&r.elapsedSeconds>0&&sameID(r.audioVersionID,plan.audioVersionID)&&f.focuSee.observedState==='recording'&&Date.now()-Date.parse(f.focuSee.observedAt)<1800){started=true;break}}
  await sleep(10);
 }
 if(!started)throw Error('Playback/recording start was not observed');
 const results=[],clock=()=>mode==='record'?fresh(path.join(appRoot,'Runtime/approved-audio-recording.json')).elapsedSeconds:valid(run).elapsed;
 for(const [i,step] of plan.actions.entries()){
  while(clock()<step.atSeconds){valid(run);await sleep(10)}
  const p=valid(run),f=feedback();if(mode==='practice'&&!['practicing','waitingForActions'].includes(p.phase))throw Error('Practice is no longer active');if(mode==='record'&&(p.phase!=='recording'||f.focuSee.observedState!=='recording'))throw Error('Capture is no longer observed recording');
  const startedAtSeconds=clock();await perform(scene.config.actions[i]);const completedAtSeconds=clock();
  results.push({actionID:step.id,startedAtSeconds,completedAtSeconds,succeeded:true,...(mode==='record'?{captureState:feedback().focuSee.observedState}:{})});
 }
 const ending=await observe();atomic(path.join(scene.dir,`${run}-${mode}-actions.json`),{results,ending});scene.lastActionEnding=ending;
 await appCommand(mode==='record'?'recordFinish':'finish',{results});emit('actionsFinished',{mode,runID:run,results});
}
// Compare what viewers will actually see. Labels and regenerated IDs are not improvements.
function actionSignature(actions){
 return hash(actions.map(({verb,app,target,end,systemOverlay,text,paste,key,scroll,cue,atSeconds})=>({verb,app,target,end,systemOverlay,text,paste,key,scroll,cue,atSeconds})));
}
function practicedPath(sessionID){return path.join(root,'scenes',sessionID,'practiced-actions.json')}
function priorPractice(sessionID){
 const file=practicedPath(sessionID);
 if(fs.existsSync(file))return read(file);
 // Recover a practice completed before the improvement gate was installed.
 const dir=path.dirname(file),config=path.join(dir,'scene.json');
 if(!fs.existsSync(config))return null;
 const attempts=fs.readdirSync(dir).filter(n=>n.endsWith('-practice-actions.json'))
  .sort((a,b)=>fs.statSync(path.join(dir,b)).mtimeMs-fs.statSync(path.join(dir,a)).mtimeMs);
 if(!attempts.length)return null;
 const actions=read(config).actions,runID=attempts[0].split('-practice-actions.json')[0];
 const prior={runID,signature:actionSignature(actions),actions};
 atomic(file,prior);return prior;
}
async function runPractice(p){
 const run=p.runID;publish({phase:'preparingPractice',message:'Resolving saved word cues and restoring the start.'});
 const replay=p.pendingEvent?.kind==='practiceReplayRequested';
 if(replay && (!sameID(p.plan?.id,scene.plan?.id)||hash(scene.config.actions)!==scene.boundConfigHash))throw Error('The rehearsal changed; request an improved practice.');
 const plan=replay?scene.plan:resolvePlan(read(p.contextPath));scene.plan=plan;scene.boundRun=run;scene.boundConfigHash=hash(scene.config.actions);
 await appCommand('acknowledge',{eventID:p.pendingEvent.id});if(!replay)await appCommand('plan',{plan});
 const gate=await restore(run,`${run}-practice`);valid(run);
 await connect();await desktop.view({app:scene.config.startingApp,max:scene.config.maxElements??200});lastReadApp=scene.config.startingApp;
 publish({phase:'practicing',message:'Prepared actions follow the approved audio clock.'});
 atomic(practicedPath(scene.config.sessionID),{runID:run,signature:actionSignature(scene.config.actions),actions:scene.config.actions});
 const action=execute(run,'practice',plan);action.catch(()=>{});
 try{await appCommand('start',{gate});await action}catch(error){throw error}
 publish({phase:'waitingForApproval',message:'Practice finished. Waiting for the user’s next decision.'});
}
async function runRecord(p){
 const run=p.runID;if(!sameID(run,scene.boundRun)||!sameID(p.plan?.id,scene.plan?.id)||hash(scene.config.actions)!==scene.boundConfigHash)throw Error('Recording plan differs from the practiced plan');
 await appCommand('acknowledge',{eventID:p.pendingEvent.id});publish({phase:'preparingRecording',message:'Restoring the practiced starting checkpoint.'});
 const manual=p.phase==='manualRestoreRequested';
 const gate=await restore(run,`${run}-${manual?'manual':'record'}`);valid(run);
 if(manual){
  await appCommand('manualReady',{gate});
  publish({phase:'prepared',message:'Starting screen restored. Waiting for the user to record manually.'});
  return;
 }
 while(valid(run).promptBusy)await sleep(20);
 await connect();await desktop.view({app:scene.config.startingApp,max:scene.config.maxElements??200});lastReadApp=scene.config.startingApp;
 const action=execute(run,'record',scene.plan);action.catch(()=>{});publish({phase:'recording',message:'Executing the same practiced action plan.'});
 await appCommand('record',{gate});await action;
 const until=Date.now()+45000;
 while(Date.now()<until){
  const state=practice();
  if(!sameID(state.runID,run)||!sameID(state.approval?.draft?.sessionID,scene.config.sessionID))throw Error('Recording identity changed before completion.');
  if(state.recordingResult && (state.phase==='completed'||(state.phase==='inactive' && state.recordActionsFinished)||sameID(guide().pendingEndingSessionID,scene.config.sessionID))){
   scene.finishedRecording={run,result:state.recordingResult};break;
  }
  valid(run);await sleep(25);
 }
 if(!scene.finishedRecording)throw Error('Recording completion was not received');
 await saveEnding();
}
async function saveEnding(){
 const {run,result}=scene.finishedRecording;
 const pauseUntil=Date.now()+3000;while(Date.now()<pauseUntil&&feedback().focuSee.observedState!=='paused')await sleep(25);paused();
 // Navigation can finish after the last click. Capture the settled, paused
 // screen for the next scene instead of requiring the loading frame to persist.
 let ending,shots;
 const settleUntil=Date.now()+5000;
 for(;;){
  paused();
  ending=await observe();
  shots=await images(`${run}-ending`);
  await sleep(100);
  if(stable(comparableSnapshot(await observe()))===stable(comparableSnapshot(ending)))break;
  if(Date.now()>=settleUntil)throw Error('The ending screen is still changing after pause.');
 }
 paused();
 const file=path.join(scene.dir,'ending-checkpoint.json');atomic(file,{checkpointID:randomUUID(),snapshot:ending,cursor:ending.cursor,images:shots,operationalOnly:true,footageNeedsReview:true,recordingResult:result});
 const review=guide();
 if(sameID(review.pendingEndingSessionID,scene.config.sessionID) || (review.remainingChapterScenes && sameID(review.draft?.sessionID,scene.config.sessionID))){
  const id=randomUUID(),root=path.join(appRoot,'GuidedNarrationReview');
  atomic(path.join(root,'commands',id+'.json'),{schemaVersion:1,id,createdAt:utc(),sessionID:scene.config.sessionID,kind:'chapterTakeCompleted'});
  const receipt=path.join(root,'receipts',id+'.json'),deadline=Date.now()+15000;
  while(!fs.existsSync(receipt)){
   if(Date.now()>=deadline)throw Error('Next-scene handoff timed out. Check the guided review before retrying.');
   await sleep(25);
  }
  const response=read(receipt);
  if(!response.accepted)throw Error('Next-scene handoff failed: '+response.message);
 }
 scene.complete=true;publish({phase:'sceneComplete',message:'Scene recorded; saved footage still needs normal review.',endingCheckpoint:file});emit('sceneComplete',{sessionID:scene.config.sessionID,endingCheckpoint:file});
}
async function prepare(config){
 if(job)throw Error('Runner is busy');if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(config.sessionID??''))throw Error('Scene sessionID must be a UUID');if(!config.sessionID||!config.startingApp||!config.observeApps?.includes(config.startingApp)||!config.actions?.length)throw Error('Scene needs sessionID, startingApp, observeApps and actions');
 [...config.actions,...(config.restoreActions??[])].forEach(validateAction);if(new Set(config.actions.map(a=>a.id)).size!==config.actions.length)throw Error('Action IDs must be unique');
 const p=practice(),g=guide();
 const requestedPractice=p.phase==='practiceRequested'&&sameID(p.approval?.draft?.sessionID,config.sessionID);
 if(g.active && g.remainingChapterScenes && (!requestedPractice || !sameID(g.draft.sessionID,config.sessionID)))throw Error('Wait for the user to select guided practice before preparing screen actions for this chapter.');
 if(p.active&&!['completed','inactive'].includes(p.phase)&&!requestedPractice)throw Error('Finish/end the current guided scene before preparing another');
 const previous=priorPractice(config.sessionID);
 if(requestedPractice && previous && !sameID(previous.runID,p.runID)){
  if(actionSignature(config.actions)===previous.signature)throw Error('The user requested improved practice. Revise the screen actions or their timing.');
  config.baselinePath=path.join(root,'scenes',config.sessionID,'baseline.json');
 }
 paused();scene={config,preparedRun:requestedPractice?p.runID:null,dir:path.join(root,'scenes',config.sessionID),complete:false};fs.mkdirSync(scene.dir,{recursive:true,mode:0o700});atomic(path.join(scene.dir,'scene.json'),config);
 publish({phase:'preparing',message:'Warming the action runner and saving the immutable starting checkpoint.',sceneID:config.sceneID,sessionID:config.sessionID});
 await connect();await minimizeCodex();await activate(config.startingApp);const cursor=await desktop.actions.cursor();await desktop.move({x:cursor.x+.5,y:cursor.y+.5});
 await bindTargets();
 await activate(config.startingApp);const snapshot=await observe();
 if(config.baselinePath){const inherited=read(config.baselinePath);assertSnapshot(snapshot,inherited.snapshot);scene.baseline={...inherited,cursor:inherited.cursor??inherited.snapshot.cursor};}
 else{scene.baseline={checkpointID:randomUUID(),snapshot,cursor:snapshot.cursor};const shots=await images('initial');assertSnapshot(await observe(),snapshot);scene.baseline.images=shots;}
 await compareImages(scene.baseline.images,scene.baseline.images);
 atomic(path.join(scene.dir,'baseline.json'),scene.baseline);publish({phase:'prepared',message:'Scene actions and starting checkpoint prepared. Narration can be announced now.'});emit('prepared',{sessionID:config.sessionID});
}
function launch(fn){job=fn().catch(async error=>{if(!String(error.message).startsWith('CANCELLED:')){attention(error.message);try{const p=practice();if(p.active&&['practicing','recording','waitingForActions','waitingForRecordActions'].includes(p.phase))await appCommand('abort')}catch{}}}).finally(()=>{job=null});}
async function commands(){
 for(const name of fs.readdirSync(path.join(root,'commands')).filter(n=>n.endsWith('.json')).sort()){
  const receipt=path.join(root,'receipts',name);if(fs.existsSync(receipt))continue;
  try{const c=read(path.join(root,'commands',name));const age=Date.now()-Date.parse(c.createdAt);if(!Number.isFinite(age)||age< -5000||age>120000||name!==c.id+'.json')throw Error('Runner command expired or has invalid identity');
   if(c.kind==='prepare'){if(job)throw Error('Runner is busy');launch(()=>prepare(c.scene));}
   else if(c.kind==='evidence'){if(!evidence||c.requestID!==evidence.id)throw Error('No matching evidence request');const pending=evidence;evidence=null;pending.resolve(c.manifest);}
   else if(c.kind==='update'){
    const g=guide(),p=practice();const wordReview=sameID(g.draft?.sessionID,scene?.config.sessionID)&&['improving','reading','awaitingDecision','audioGenerating','audioReady'].includes(g.phase);if(job||!scene||(!wordReview&&p.phase!=='practiceRequested')||!sameID(c.scene.sessionID,scene.config.sessionID))throw Error('Actions can only change before a new practice, with no active job');
    if(!Array.isArray(c.scene.actions)||!c.scene.actions.length)throw Error('Provide at least one improved action.');
    c.scene.actions.forEach(validateAction);
    if(c.scene.restoreActions)c.scene.restoreActions.forEach(validateAction);
    if(new Set(c.scene.actions.map(a=>a.id)).size!==c.scene.actions.length)throw Error('Action IDs must be unique.');
    if(!wordReview && !sameID(p.approval?.draft?.sessionID,scene.config.sessionID))throw Error('The active practice belongs to another scene.');
    const previous=priorPractice(scene.config.sessionID);
    if(p.phase==='practiceRequested' && p.pendingEvent?.kind==='practiceReplayRequested')throw Error('Replay uses the existing practiced actions.');
    if(p.phase==='practiceRequested' && previous && !sameID(previous.runID,p.runID)){
     if(!sameID(c.runID,p.runID))throw Error('Use the current practice request run ID.');
     if(actionSignature(c.scene.actions)===previous.signature)throw Error('Change the demonstrated actions or timing before practicing again.');
    }
    if(p.pendingEvent?.instruction && p.phase==='practiceRequested' && !sameID(c.runID,p.runID))throw Error('Use the current improvement request run ID.');
    scene.preparedRun=p.phase==='practiceRequested'?p.runID:null;
    scene.config.actions=c.scene.actions;
    if(c.scene.restoreActions)scene.config.restoreActions=c.scene.restoreActions;
    scene.boundRun=null;scene.targets={};
    atomic(path.join(scene.dir,'scene.json'),scene.config);
    publish({phase:'prepared',reason:null,message:'Updated actions will be practiced before they can be recorded.'});
   }
   else if(c.kind==='resume'){if(job||!scene)throw Error('No stopped scene is ready to resume');if(scene.finishedRecording&&!scene.complete){launch(saveEnding)}else{if(practice().phase==='practiceRequested')scene.boundRun=null;publish({phase:'prepared',message:'Retrying the current gate; approvals are not synthesized.'});}}
   else if(c.kind==='stop'){stopped=true;if(evidence){evidence.reject(Error('CANCELLED: runner stopped'));evidence=null;}try{const p=practice();if(p.active&&['practicing','recording','waitingForActions','waitingForRecordActions'].includes(p.phase))await appCommand('abort')}catch{}}
   else throw Error('Unknown runner command');atomic(receipt,{accepted:true,commandID:c.id});
  }catch(error){atomic(receipt,{accepted:false,message:error.message})}
 }
}
publish();
try{while(!stopped){
 await commands();
 if(!job && (!scene || scene.complete || state.phase==='prepared' || state.phase==='needsAgent')){
  // A chapter started in the app can request help before any runner plan exists.
  try {
   const g=guide();
   if(g.active && g.remainingChapterScenes && !sameID(g.draft.sessionID,scene?.config.sessionID)){
    const wording=g.phase==='improving';
    const practiceNeeded=g.practice?.phase==='practiceRequested';
    if(wording || practiceNeeded){
     const key=wording?g.decision.id:g.practice.runID;
     if(key!==lastChapterRequest){
      lastChapterRequest=key;
      publish({phase:'needsAgent',message:wording?'Chapter wording revision requested.':'Prepare guided actions for the selected chapter scene.'});
      const instruction=wording?g.decision.instruction:g.practice.instruction;
      emit(wording?'narrationImprovementRequested':'needsAgent',{sessionID:g.draft.sessionID,sceneID:g.draft.sceneID,event:g.decision,...(instruction?{instruction}:{})});
     }
    }
   }
  }catch(error){if(error.code!=='ENOENT' && state.phase!=='needsAgent')attention(error.message)}
 }
 if(!job&&scene?.baseline&&!scene.complete){
  try{
   const g=guide();
   if(sameID(g.draft?.sessionID,scene.config.sessionID)&&g.phase==='improving'&&!sameID(g.decision?.id,scene.improvementID)){
    scene.improvementID=g.decision.id;scene.improvementRevision=g.draft.revision;
    publish({phase:'needsAgent',reason:'narrationImprovement',message:'The user requested improved narration.'});emit('narrationImprovementRequested',{event:g.decision});
   }else if(state.reason==='narrationImprovement'&&sameID(g.draft?.sessionID,scene.config.sessionID)&&g.draft.revision>scene.improvementRevision){
    publish({phase:'prepared',reason:null,message:'Revised narration received; prepared actions remain ready.'});emit('narrationUpdated',{revision:g.draft.revision});
   }
   if(state.phase!=='needsAgent'){
    const p=practice();if(sameID(p.approval?.draft?.sessionID,scene.config.sessionID)){
     if(p.phase==='practiceRequested'&&!sameID(scene.boundRun,p.runID)){
      const prior=priorPractice(scene.config.sessionID);
      const instruction=p.pendingEvent?.instruction;
      const needsRevision=prior && !sameID(prior.runID,p.runID) && prior.signature===actionSignature(scene.config.actions);
      if(p.pendingEvent?.kind!=='practiceReplayRequested' && (needsRevision || (instruction && !sameID(scene.preparedRun,p.runID)))){
       publish({phase:'needsAgent',reason:'practiceImprovement',message:'The user requested improved screen actions. Update this practice before running it.'});
       emit('practiceImprovementRequested',{sessionID:scene.config.sessionID,sceneID:scene.config.sceneID,runID:p.runID,...(instruction?{instruction}:{})});
      }else launch(()=>runPractice(p));
     }
     else if(['recordRequested','manualRestoreRequested'].includes(p.phase))launch(()=>runRecord(p));
    }
   }
  }catch(error){attention(error.message)}
 }
 await sleep(30);if(Date.now()-Date.parse(state.updatedAt)>900)publish();
}}

finally{if(job)await job;desktop?.close();publish({running:false,phase:'stopped',message:'Runner stopped; no new screen actions will run.'})}
