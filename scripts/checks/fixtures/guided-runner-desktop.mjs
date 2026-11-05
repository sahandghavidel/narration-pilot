// Isolated test driver: never imports native UI libraries or controls real apps.
import fs from 'node:fs';import path from 'node:path';import{execFileSync}from'node:child_process';
const root=process.env.GUIDED_RUNNER_FIXTURE_ROOT;
if(!root)throw Error('Fixture root required');
let text='0',cursor={x:0,y:100},active='ChatGPT',reads=0;
function trace(verb,value){const p=JSON.parse(fs.readFileSync(path.join(root,'GuidedNarrationReview/Practice/status.json')));fs.appendFileSync(path.join(root,'trace.jsonl'),JSON.stringify({verb,value,phase:p.phase,runID:p.runID})+'\n');fs.writeFileSync(path.join(root,'ui.json'),JSON.stringify({text,cursor}));}
export class Persona{constructor(){}thinkTimeMs(){return 0}traits(){return{speedFactor:1,dwellScale:1}}}
export class DesktopService{constructor(){this.cursor=async()=>({...cursor})}}
const buttons=[['One',10],['Equals',50],['All Clear',90]];
export class Desktop{
 constructor(service){this.actions=service}
 async apps(){const marker=path.join(root,'codex-front');if(fs.existsSync(marker)){active='ChatGPT';fs.unlinkSync(marker)}return [{name:'Calculator',bundleId:'fixture.Calculator',active:active==='Calculator'},{name:'ChatGPT',bundleId:'com.openai.codex',active:active==='ChatGPT'}]}
 async activate(app){active=app;trace('activate',app);return{name:app,bundleId:app==='ChatGPT'?'com.openai.codex':'fixture.'+app,pid:1,active:true}}
 async key(combo){if(combo!=='cmd+m'||active!=='ChatGPT')throw Error('Unexpected minimize target');trace('minimize','ChatGPT');active='Calculator'}
 async view({app='Calculator'}={}){return{app:{name:app,bundleId:'com.google.Chrome',pid:1},window:{title:text==='0'?app:'Result',x:0,y:0,w:100,h:120},elements:[{ref:'tab',role:'radio',name:`Fixture tab - Memory usage - ${++reads}.2 MB`,rect:{x:0,y:0,width:10,height:10}},{ref:'text',role:'text',name:text,rect:{x:0,y:0,width:100,height:20}},...buttons.map(([name,x])=>({ref:name,role:'button',name,enabled:true,rect:{x,y:40,width:10,height:10}}))]}}
 async move(p){cursor={x:Math.floor(p.x),y:Math.floor(p.y)};trace('move',cursor)}
 async click(p){cursor={x:p.x,y:p.y};const name=buttons.find(([,x])=>x+5===p.x)?.[0];if(name==='All Clear')text='0';if(name==='One')text='1';if(name==='Equals')text='20';trace('click',name);await new Promise(r=>setTimeout(r,10))}
 async screenshot({path:file}){if(process.env.GUIDED_RUNNER_DENY_CAPTURE==='1')throw Error('Fixture screen permission denied');let color=text==='0'?0:100;if(process.env.GUIDED_RUNNER_BAD_RECORD_IMAGE==='1'&&file.includes('-record-'))color=200;execFileSync('python3',['-c','from PIL import Image; import sys; Image.new("RGB",(100,120),(int(sys.argv[1]),0,0)).save(sys.argv[2],format="PNG")',String(color),file]);return file}
 close(){}
}
