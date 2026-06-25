# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2024 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

import globalPluginHandler
import ui
import api
from logHandler import log
is_python_3_or_above = (lambda x: [x for x in [False]] and None or x)(True)
if is_python_3_or_above:
	import threading
else:
	import thread
import time
import os
import globalCommands
import tones
import json
import speech
import braille
import appModuleHandler
import queueHandler
import buildVersion
import types
import re

stopThreads=False
eltenindex=None
eltenindexid=None

if is_python_3_or_above:
	class EltenIndexCallback(speech.commands.BaseCallbackCommand):
		def __init__(self, index, indid=None):
			self.index = index
			self.indid=indid
		def run(self):
			global eltenindex
			global eltenindexid
			global eltenqueue
			eltenindex=self.index
			eltenindexid=self.indid
			eltenqueue['indexes'].append({'index':self.index, 'indid':self.indid})
		def __repr__(self):
			return "EltenIndexCallback({index}, {indid})".format(
				index=self.index,indid=self.indid)

	class EltenEmptyCallback(speech.commands.BaseCallbackCommand):
		def run(self): pass
		def __repr__(self): return "EltenEmptyCallback()"

eltenmod=None
eltenbraille = braille.BrailleBuffer(braille.handler)
eltenbrailletext=""
eltenqueue={'gestures':[], 'indexes':[], 'statuses':[], 'returns':[]}
eltenpipein=None
eltenpipeout=None
eltenpipest=None



ostc = speech.speakTypedCharacters
def stc(ch):
	global eltenmod
	if(appModuleHandler.getAppModuleForNVDAObject(api.getForegroundObject())!=eltenmod):
		return ostc(ch)

speech.speakTypedCharacters=stc

class GlobalPlugin(globalPluginHandler.GlobalPlugin):

	def elten_thread(threadName=None):
		global stopThreads
		wrongpipeid=""
		global eltenmod
		global eltenqueue
		nvdapipeid=""
		global eltenpipein
		global eltenpipeout
		global eltenpipest
		eltenpipein=None
		eltenpipeout=None
		eltenpipest=None
		eltendata = os.getenv("appdata")+"\\elten"
		eltentemp = os.getenv("temp")+"\\elten"
		nvdapipefile = eltentemp+"\\nvda.pipe"
		while(1):
			if(stopThreads): break
			try:
				if(nvdapipeid!=""):
					if(appModuleHandler.getAppModuleForNVDAObject(api.getForegroundObject())==eltenmod): time.sleep(0.001)
					else: time.sleep(0.1)
					str=eltenpipein.readline()
					if(len(str)>0):
						if(is_python_3_or_above): str=str.decode("utf-8", errors="ignore")
						j = json.loads(str)
						id=j['id']
						asnc=False
						if('async' in j): asnc=j['async']
						j=elten_command(j)
						j['id']=id
						if(asnc!=False): j['msgtype']=1
						w=json.dumps(j)+"\n"
						if(is_python_3_or_above): w=w.encode("utf-8")
						if(asnc==False): eltenpipeout.write(w)
						else: eltenqueue['returns'].append(w)
				else:
					time.sleep(0.1)
				if(os.path.isfile(nvdapipefile)):
					file = open(nvdapipefile,mode='r')
					pipeid = file.read()
					file.close()
					if(pipeid!=nvdapipeid and pipeid!=wrongpipeid):
						try:
							nvdapipeid=pipeid
							eltenpipein=open("\\\\.\\pipe\\"+nvdapipeid+"out", 'rb', 0)
							eltenpipeout=open("\\\\.\\pipe\\"+nvdapipeid+"in", 'wb', 0)
							eltenpipest=open("\\\\.\\pipe\\"+nvdapipeid+"st", 'wb', 0)
							eltenqueue['statuses'].append("connected")
							if(is_python_3_or_above): 							eltenqueue['statuses'].append("cbckindexing")
						except:
							log.exception("Elten pipe")
							wrongpipeid=pipeid
							nvdapipeid=""
							try: os.remove(nvdapipefile)
							except: pass
				elif(nvdapipeid!=""):
					nvdapipeid=""
					eltenpipein.close()
					eltenpipeout.close()
					eltenpipest.close()
					eltenpipein=None
					eltenpipeout=None
					eltenpipest=None
			except Exception as Argument:
				log.exception("Elten: main thread")

	def elten_braille_thread(threadName=None):
		global stopThreads
		global eltenmod
		global eltenbraille
		global eltenbrailletext
		oldbraille=eltenbrailletext
		while(True):
			if(stopThreads): break
			time.sleep(0.1)
			if(eltenmod!=None and eltenbraille!=None):
				if(appModuleHandler.getAppModuleForNVDAObject(api.getForegroundObject())==eltenmod and eltenbraille!=None and braille.handler.buffer!=eltenbraille and braille.handler.buffer!=braille.handler.messageBuffer):
					braille.handler.buffer=eltenbraille
					queueHandler.queueFunction(queueHandler.eventQueue,braille.handler.update)
				elif(braille.handler!=None and appModuleHandler.getAppModuleForNVDAObject(api.getForegroundObject())!=eltenmod and braille.handler.buffer==eltenbraille):
					braille.handler.buffer=braille.handler.mainBuffer
					queueHandler.queueFunction(queueHandler.eventQueue,braille.handler.update)
				if oldbraille!=eltenbrailletext:
					oldbraille=eltenbrailletext
					queueHandler.queueFunction(queueHandler.eventQueue,braille.handler.update)

	def elten_queue_thread(threadName=None):
		global stopThreads
		global eltenqueue
		global eltenpipest
		global eltenindex
		global eltenindexid
		global eltenmod
		lastSend=0
		while(True):
			if(stopThreads): break
			time.sleep(0.01)
			try:
				if(eltenpipest!=None and eltenpipest!=-1 and len(eltenqueue['gestures'])>0):
					r=eltenqueue['gestures'][:]
					eltenqueue['gestures']=[]
					j={'msgtype':2, 'gestures':r}
					w=json.dumps(j)+"\n"
					if(is_python_3_or_above): w=w.encode("utf-8")
					eltenpipest.write(w)
					lastSend=time.time()
				if(eltenpipest!=None and eltenpipest!=-1 and len(eltenqueue['indexes'])>0):
					r=eltenqueue['indexes'][:]
					eltenqueue['indexes']=[]
					j={'msgtype':3, 'indexes':r}
					w=json.dumps(j)+"\n"
					if(is_python_3_or_above): w=w.encode("utf-8")
					eltenpipest.write(w)
					lastSend=time.time()
				if(eltenpipest!=None and eltenpipest!=-1 and len(eltenqueue['statuses'])>0):
					r=eltenqueue['statuses'][:]
					eltenqueue['statuses']=[]
					j={'msgtype':4, 'statuses':r}
					w=json.dumps(j)+"\n"
					if(is_python_3_or_above): w=w.encode("utf-8")
					eltenpipest.write(w)
					lastSend=time.time()
				if(eltenpipest!=None and eltenpipest!=-1 and len(eltenqueue['returns'])>0):
					r=eltenqueue['returns'][:]
					eltenqueue['returns']=[]
					for w in r:
						eltenpipest.write(w)
					lastSend=time.time()
				if(lastSend<time.time()-1 and appModuleHandler.getAppModuleForNVDAObject(api.getForegroundObject())==eltenmod):
					eltenqueue['statuses'].append("noop")
					lastSend=time.time()
			except Exception as Argument:
				log.exception("Elten: queue thread")
				time.sleep(0.05)
				eltenqueue={'gestures':[], 'indexes':[], 'statuses':[], 'returns':[]}

	if is_python_3_or_above:
		t1=threading.Thread(target=elten_thread)
		t1.daemon=True
		t1.start()
		t2=threading.Thread(target=elten_braille_thread)
		t2.daemon=True
		t2.start()
		t3=threading.Thread(target=elten_queue_thread)
		t3.daemon=True
		t3.start()
	else:
		thread.start_new_thread ( elten_thread, ('elten', ))
		thread.start_new_thread ( elten_braille_thread, ('elten_braille', ))
		thread.start_new_thread ( elten_queue_thread, ('elten_queue', ))

	def terminate(self):
		stopThreads=True
		time.sleep(0.1)

def elten_command(ac):
	global eltenmod
	global eltenbraille
	global eltenbrailletext
	global eltenindex
	global eltenindexid
	global eltenqueue
	try:
		if(('ac' in ac)==False): return {}
		if(ac['ac']=="speak"):
			eltenindex=None
			eltenindexid=None
			text=""
			if('text' in ac): text=ac['text']
			if(speech.isBlank(text)==False): queueHandler.queueFunction(queueHandler.eventQueue,speech.speakText,text)
		if(ac['ac']=="speakspelling"):
			eltenindex=None
			eltenindexid=None
			text=""
			if('text' in ac): text=ac['text']
			if(len(text)>0): queueHandler.queueFunction(queueHandler.eventQueue,speech.speakSpelling,text)
		if(ac['ac']=="speakindexed"):
			eltenindex=None
			eltenindexid=None
			texts=[]
			indexes=[]
			indid=None
			if('texts' in ac): texts=ac['texts']
			if('indexes' in ac): indexes=ac['indexes']
			if('indid' in ac): indid=ac['indid']
			v=[]
			text_added = False
			for i in range(0, len(texts)):
				if is_python_3_or_above:
					if(speech.isBlank(texts[i])): continue
					if(i<len(indexes)): v.append(EltenIndexCallback(indexes[i], indid))
					if(i<len(indexes) and i>0 and texts[i-1]!="" and texts[i-1][-1]=="\n") and speech.commands is not None and text_added:
						v.append(speech.commands.EndUtteranceCommand())
						text_added = False
				else:
					eltenindexid=indid
					if(i<len(indexes)): v.append(speech.IndexCommand(indexes[i]))
				v.append(texts[i].replace("\n", " "))
				text_added = True
			log.info(v.__repr__())
			queueHandler.queueFunction(queueHandler.eventQueue,speech.cancelSpeech)
			queueHandler.queueFunction(queueHandler.eventQueue,speech.speak,v)
		if(ac['ac']=='stop'):
			queueHandler.queueFunction(queueHandler.eventQueue,speech.cancelSpeech)
			eltenindex=None
			eltenindexid=None
		if(ac['ac']=='sleepmode'):
			st=eltenmod.sleepMode
			if('st' in ac): st=ac['st']
			eltenmod.sleepMode=st
			return {'st': st}
		if(ac['ac']=='init'):
			pid=0
			if('pid' in ac): pid=ac['pid']
			eltenmod = appModuleHandler.getAppModuleFromProcessID(pid)
			def script_eltengesture(self, gesture):
				global eltenqueue
				eltenqueue['gestures']+=gesture.identifiers
			eltenmod.__class__.script_eltengesture = types.MethodType(script_eltengesture, eltenmod.__class__)
			eltenmod.bindGesture('kb(laptop):NVDA+A', 'eltengesture')
			eltenmod.bindGesture('kb(laptop):NVDA+L', 'eltengesture')
			eltenmod.bindGesture('kb(desktop):NVDA+downArrow', 'eltengesture')
			eltenmod.bindGesture('kb(desktop):NVDA+upArrow', 'eltengesture')
		if(ac['ac']=='braille'):
			text=""
			if('text' in ac): text=ac['text']
			if('type' in ac and 'index' in ac):
				if ac['type']==-1: text=eltenbrailletext[:ac['index']]+eltenbrailletext[ac['index']+1:]
				elif ac['type']==1: text=eltenbrailletext[:ac['index']]+text+eltenbrailletext[ac['index']:]
			eltenbrailletext=text+" "
			regions=[]
			for phrase in re.split("([.,:/\n?!])", eltenbrailletext):
				if phrase=="": continue
				if len(regions)>10000: continue;
				region=braille.TextRegion(phrase)
				if hasattr(region, 'parseUndefinedChars'): region.parseUndefinedChars=False
				region.update()
				regions.append(region)
			eltenbraille.regions=regions
			if('pos' in ac): 
				poses = eltenbraille.rawToBraillePos
				if(ac['pos']<len(text) and ac['pos']<len(poses)):
					reg, pos = eltenbraille.bufferPosToRegionPos(poses[ac['pos']])
					eltenbraille.scrollTo(reg, pos)
			if('cursor' in ac and ac['cursor'] is not None):
				poses = eltenbraille.rawToBraillePos
				reg, pos = eltenbraille.bufferPosToRegionPos(poses[ac['cursor']])
				reg.cursorPos=reg.brailleToRawPos[pos]
				reg.update()
			eltenbraille.update()
			braille.handler.update()
		if(ac['ac']=='braillepos' and 'pos' in ac and len(eltenbraille.regions)>0):
			poses = eltenbraille.rawToBraillePos
			if(ac['pos']<len(poses)):
				reg, pos = eltenbraille.bufferPosToRegionPos(poses[ac['pos']])
				eltenbraille.scrollTo(reg, pos)
				reg.update()
			if('cursor' in ac and ac['cursor'] is not None):
				reg, pos = eltenbraille.bufferPosToRegionPos(poses[ac['cursor']])
				reg.cursorPos=reg.brailleToRawPos[pos]
				reg.update()
			eltenbraille.update()
			braille.handler.update()
		if(ac['ac']=='getversion'):
			return {'version': 44}
		if(ac['ac']=='getnvdaversion'):
			return {'version': buildVersion.version}
		if(ac['ac']=='getindex'):
			if(is_python_3_or_above):
				return {'index': eltenindex, 'indid': eltenindexid}
			else:
				return {'index': speech.getLastSpeechIndex(), 'indid': eltenindexid}
	except Exception as Argument:
		log.exception("Elten: command thread")
		return {}
	return {}