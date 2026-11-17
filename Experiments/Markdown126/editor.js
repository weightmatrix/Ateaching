import {EditorState} from '@codemirror/state';
import {EditorView, lineNumbers} from '@codemirror/view';
import {markdown} from '@codemirror/lang-markdown';
let view;
const frame=()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));
window.loadMarkdown=async text=>{
 view?.destroy(); const start=performance.now();
 view=new EditorView({state:EditorState.create({doc:text,extensions:[lineNumbers(),markdown(),EditorView.lineWrapping]}),parent:document.querySelector('#editor')});
 await frame();return performance.now()-start;
};
window.benchmark=async text=>{
 const open=await window.loadMarkdown(text);const edits=[],sync=[];
 for(let i=0;i<40;i++){
  const from=Math.floor(view.state.doc.length/2); const start=performance.now();
  view.dispatch({changes:{from,insert:'测'},selection:{anchor:from+1},scrollIntoView:true});
  sync.push(performance.now()-start); await frame();edits.push(performance.now()-start);
 }
 edits.sort((a,b)=>a-b);sync.sort((a,b)=>a-b);
 return {editP50DispatchMs:sync[20],editP95DispatchMs:sync[38],utf16:text.length,openMs:open,editP50FrameMs:edits[20],editP95FrameMs:edits[38],renderedLines:document.querySelectorAll('.cm-line').length,textKit2:null};
};
document.querySelector('#file').onchange=async event=>{
 const file=event.target.files[0];if(file)document.querySelector('#result').textContent=JSON.stringify(await window.benchmark(await file.text()),null,2);
};
