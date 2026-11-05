#!/usr/bin/env python3
"""End-to-end runner checks with fake app files/desktop; no native UI or audio."""
import copy
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time
import unittest
import uuid
from PIL import Image

REPO = Path(__file__).resolve().parents[2]
CLI = REPO / 'scripts/guided-session.py'
SDK = Path(__file__).parent / 'fixtures/guided-runner-desktop.mjs'
now = lambda: datetime.now(timezone.utc).isoformat()
uid = lambda: str(uuid.uuid4()).upper()


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(value))
    temporary.replace(path)


class App:
    def __init__(self, root):
        self.root = root
        self.sid, self.audio = uid(), uid()
        self.guide = dict(active=False, phase='inactive')
        self.state = dict(active=False, phase='inactive', promptBusy=False)
        self.context = dict(audioVersionID=self.audio, audioSHA256='fixture-hash', duration=.35,
                            words=[dict(word='One', start=0, end=.1), dict(word='Equals', start=.12, end=.2)])
        write(root/'context.json', self.context)
        previous = root/'Runtime/approved-audio-recording.json'
        write(previous, dict(busy=False, phase='completed', elapsedSeconds=0))
        os.utime(previous, (time.time()-86400, time.time()-86400))
        self.capture, self.take, self.started, self.mode = 'paused', uid(), 0, None
        self.starting_text = '0'
        self.practice_finishes, self.record_starts, self.errors = 0, 0, []
        self.done = False
        (root/'GuidedNarrationReview/Practice/commands').mkdir(parents=True)
        (root/'GuidedNarrationReview/Practice/receipts').mkdir()
        self.thread = threading.Thread(target=self.loop)
        self.thread.start()

    def request(self):
        self.state.update(active=True, phase='practiceRequested', runID=uid(), attempt=self.practice_finishes+1,
                          approval=dict(draft=dict(sessionID=self.sid)), contextPath=str(self.root/'context.json'),
                          pendingEvent=dict(id=uid(),kind='practiceRequested'), plan=None, elapsed=0)
        self.mode = None

    def loop(self):
        base = self.root/'GuidedNarrationReview/Practice'
        while not self.done:
            try:
                for path in (base/'commands').glob('*.json'):
                    receipt = base/'receipts'/path.name
                    if receipt.exists(): continue
                    cmd = json.loads(path.read_text())
                    if cmd['runID'].lower() != self.state['runID'].lower(): raise RuntimeError('Wrong run')
                    kind = cmd['kind']
                    if kind == 'plan':
                        self.state['plan'] = copy.deepcopy(cmd['plan'])
                        self.state['plan']['id'] = self.state['plan']['id'].upper()
                    elif kind in ['start','record']:
                        assert cmd['gate']['matched'] and Path(cmd['gate']['evidencePath']).exists()
                        assert json.loads((self.root/'ui.json').read_text())['text'] == self.starting_text
                        if kind=='record':
                            assert self.state['phase']=='recordRequested'
                            self.record_starts += 1
                        self.started=time.monotonic(); self.mode=kind
                        self.state.update(phase='practicing' if kind=='start' else 'recording',elapsed=.001,results=False)
                        if kind=='record': self.capture='recording';self.take=uid()
                    elif kind in ['finish','recordFinish']:
                        if kind=='recordFinish': assert all(r['captureState']=='recording' for r in cmd['results'])
                        self.state['results']=True
                    elif kind=='abort': self.state['phase']='blocked';self.capture='paused';self.mode=None
                    elif kind!='acknowledge': raise RuntimeError('Unexpected kind '+kind)
                    write(receipt,dict(accepted=True))
                elapsed=time.monotonic()-self.started
                if self.mode:
                    self.state['elapsed']=min(.35,elapsed)
                    if elapsed>=.35 and self.state['results']:
                        if self.mode=='start':
                            self.practice_finishes+=1
                            if self.practice_finishes==1:self.request() # Fixture user's G.
                            else:self.state.update(phase='recordRequested',pendingEvent=dict(id=uid(),kind='recordRequested')) # Fixture user's A.
                        else:
                            self.state.update(phase='completed',recordingResult=dict(sessionID=self.take,duration=.35))
                            self.capture='paused'
                        self.mode=None
                common=dict(appRunning=True,pid=os.getpid(),updatedAt=now())
                write(self.root/'GuidedNarrationReview/status.json',dict(common,**self.guide))
                write(base/'status.json',dict(common,**self.state))
                write(self.root/'AgentFeedback/status.json',dict(common,focuSee=dict(observedState=self.capture,observedAt=now())))
                if self.mode=='record':
                    write(self.root/'Runtime/approved-audio-recording.json',dict(common,busy=self.mode=='record',phase='playing' if self.mode=='record' else 'completed',elapsedSeconds=min(.35,max(0,elapsed)),audioVersionID=self.audio))
            except Exception as error:
                self.errors.append(str(error));break
            time.sleep(.01)

    def close(self):
        self.done=True;self.thread.join()


class RunnerCheck(unittest.TestCase):
    def run_case(self, denied=False, bad=False, reappear=False):
        with tempfile.TemporaryDirectory(prefix='guided-session-check-') as folder:
            root=Path(folder);app=App(root/'app');worker=root/'worker'
            env=dict(os.environ,GUIDED_RUNNER_FIXTURE_ROOT=str(root/'app'),GUIDED_RUNNER_DENY_CAPTURE=str(int(denied)),GUIDED_RUNNER_BAD_RECORD_IMAGE=str(int(bad)))
            def cli(*args):
                r=subprocess.run(['python3',str(CLI),'--directory',str(worker),*args],capture_output=True,text=True,env=env,timeout=15)
                self.assertEqual(r.returncode,0,r.stderr)
                return json.loads(r.stdout)
            started=None
            try:
                time.sleep(.05)
                started=cli('start','--sdk',str(SDK),'--app-directory',str(root/'app'))
                self.assertEqual(cli('start')['pid'],started['pid'])
                config=dict(sessionID=app.sid,sceneID='fixture',startingApp='Calculator',observeApps=['Calculator'],
                            actions=[dict(id='one',description='Click One',verb='click',target=dict(name='One',role='button'),atSeconds=0,practiceSafe=True),dict(id='equals',description='Click Equals',verb='click',target=dict(name='Equals',role='button'),cue=dict(word='equals'),practiceSafe=True)],
                            restoreActions=[dict(id='clear',verb='click',target=dict(name='All Clear',role='button'),practiceSafe=True)])
                scene=root/'scene.json';scene.write_text(json.dumps(config));cli('prepare','--scene-file',str(scene))
                launched=False;improvement_sent=False;improvement_handled=False;second_scene=False
                supplied=set();until=time.monotonic()+20
                while time.monotonic()<until:
                    state=cli('status')
                    self.assertEqual(state['pid'],started['pid'])
                    if state['phase']=='needsEvidence':
                        request=state['evidenceRequest']
                        if request['id'] not in supplied:
                            ui=json.loads((root/'app/ui.json').read_text());image=root/(request['id']+'.png')
                            Image.new('RGB',(100,120),(0 if ui['text']=='0' else 100,0,0)).save(image)
                            manifest=root/'manifest.json';manifest.write_text(json.dumps(dict(capturedAt=now(),images={'Calculator':str(image)})))
                            cli('evidence','--request-id',request['id'],'--manifest',str(manifest));supplied.add(request['id'])
                    if state['phase']=='prepared' and not improvement_sent:
                        app.guide=dict(active=True,phase='improving',draft=dict(sessionID=app.sid,revision=1),decision=dict(id=uid(),kind='improveNarration'))
                        improvement_sent=True
                    if state['phase']=='needsAgent' and state.get('reason')=='narrationImprovement':
                        self.assertEqual(state['lastEvent']['kind'],'narrationImprovementRequested')
                        app.guide=dict(active=True,phase='reading',draft=dict(sessionID=app.sid,revision=2))
                        improvement_handled=True
                    elif state['phase']=='prepared' and improvement_handled and not launched:
                        app.request();launched=True
                    if state['phase']=='needsAgent' and state.get('reason')!='narrationImprovement':
                        self.assertTrue(bad,(state,app.errors))
                        self.assertIn('Visual continuity mismatch',state['message'])
                        self.assertEqual(app.record_starts,0);break
                    if state['phase']=='sceneComplete':
                        self.assertFalse(bad)
                        ending=json.loads(Path(state['endingCheckpoint']).read_text())
                        self.assertTrue(ending['footageNeedsReview'])
                        if not denied and not second_scene:
                            # Reuse the same worker for a second scene with its inherited ending checkpoint.
                            app.state.update(active=False,phase='inactive');app.guide=dict(active=False,phase='inactive');app.sid=uid();app.starting_text='20'
                            config.update(sessionID=app.sid,sceneID='fixture-next',baselinePath=state['endingCheckpoint'],
                                          actions=[dict(id='hold',verb='hold',atSeconds=0,practiceSafe=True)],restoreActions=[])
                            scene.write_text(json.dumps(config))
                            if reappear:(root/'app/codex-front').touch()
                            cli('prepare','--scene-file',str(scene))
                            launched=False;improvement_sent=False;improvement_handled=False;second_scene=True
                            continue
                        self.assertEqual(app.practice_finishes,3 if second_scene else 2)
                        self.assertEqual(app.record_starts,2 if second_scene else 1)
                        break
                    time.sleep(.02)
                else:self.fail('Runner did not finish: '+json.dumps(cli('status'))+' errors '+str(app.errors))
                self.assertFalse(app.errors,app.errors)
                if denied:self.assertGreaterEqual(len(supplied),4) # Initial, practice, redo, record, ending.
                trace=[json.loads(x) for x in (root/'app/trace.jsonl').read_text().splitlines()]
                self.assertEqual(sum(x['verb']=='minimize' for x in trace),2 if reappear else 1)
                self.assertEqual(sum(x['verb']=='activate' and x['value']=='ChatGPT' for x in trace),2 if reappear else 1)
                self.assertEqual(sum(x['verb']=='click' and x['value']=='One' for x in trace),2 if bad else 3)
                self.assertTrue(all(x['phase']!='recording' for x in trace if x['verb']=='click' and x['value']=='All Clear'))
            finally:
                if started:
                    try:cli('stop')
                    except Exception:os.kill(started['pid'],15)
                app.close()

    def test_minimize_again_only_after_codex_reappears(self):self.run_case(reappear=True)
    def test_native_capture_redo_and_record(self):self.run_case()
    def test_fresh_cua_evidence_fallback(self):self.run_case(denied=True)
    def test_visual_mismatch_blocks_recording(self):self.run_case(bad=True)


if __name__=='__main__':unittest.main()
