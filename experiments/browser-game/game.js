// No Steam binaries or game engine run here. These original demo assets use the
// browser's own graphics APIs, proving client rendering with a GPU-free server.
const canvas = document.querySelector('#game');
const status = document.querySelector('#renderer');
const gpuStatus = document.querySelector('#gpu');
const speedText = document.querySelector('#speed');
const fpsText = document.querySelector('#fps');
const startButton = document.querySelector('#start');
const intro = document.querySelector('#intro');
const loadText = document.querySelector('#loaded');
const serverText = document.querySelector('#server');
const deviceText = document.querySelector('#device-info');
const networkText = document.querySelector('#network');
const saveText = document.querySelector('#save-status');
const remoteCheckbox = document.querySelector('#remote-mode');
remoteCheckbox.checked = new URLSearchParams(location.search).get('remote') === '1';
const saveButton = document.querySelector('#save-now');
const quitButton = document.querySelector('#quit');
let sessionToken = null;
let isSaving = false;
let remoteMode = false;
let remotePending = false;
let remoteLastRequest = 0;
let remoteTarget = null;
let remoteFailures = 0;
let remoteReplies = 0;
let renderer = null;
let world = null;
let isRunning = false;
let last = 0;
let count = 0;
let elapsed = 0;
const vehicle = { x: 0, z: 0, velocity: 17, distance: 0 };
const keys = new Set();
const touches = { left: false, right: false, gas: false, brake: false };

window.__TRUCK_POC = {
  get renderer() { return renderer?.type ?? 'none'; },
  get running() { return isRunning; },
  get loaded() { return world !== null; },
  get serverFrames() { return 0; },
  get distance() { return vehicle.distance; }
};

async function probeClient() {
  // A web page can test graphics APIs, but cannot reliably inspect physical GPU
  // hardware, dedicated GPU memory, or Xbox system internals.
  const c = document.createElement('canvas');
  const gl = c.getContext('webgl2');
  const webgl2 = !!gl;
  gl?.getExtension('WEBGL_lose_context')?.loseContext();
  let webgpu = false;
  if (window.isSecureContext && navigator.gpu) {
    try { webgpu = !!(await navigator.gpu.requestAdapter()); }
    catch { webgpu = false; }
  }
  const profile = {webgpu, webgl2};
  try {
    const r = await fetch('/api/client', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(profile)});
    if (!r.ok) throw new Error('HTTP '+r.status);
    const result = await r.json();
    deviceText.textContent = 'An Server gemeldet: '+(result.render_mode || 'unbekannt')+' verfügbar';
  } catch (error) {
    deviceText.textContent = 'Erkannt: '+(webgpu?'WebGPU':webgl2?'WebGL2':'nur Canvas2D')+' · Servermeldung fehlgeschlagen';
  }
  refreshNetwork();
}
function refreshNetwork() {
  const events = performance.getEntriesByType('resource');
  const nav = performance.getEntriesByType('navigation');
  const bytes = [...nav, ...events].reduce((n, v) => n + (v.transferSize || 0), 0);
  const kib = bytes / 1024;
  networkText.textContent = kib.toFixed(1)+' KiB seit Seitenaufruf';
}
async function ensureSession() {
  try { sessionToken = window.localStorage.getItem('truck-browser-save-token'); }
  catch { sessionToken = null; }
  if (sessionToken) {
    const r = await fetch('/api/save', {headers: {'X-Game-Session': sessionToken}, cache: 'no-store'});
    if (r.ok) {
      const state = await r.json();
      if (['x','z','velocity','distance'].every(k => Number.isFinite(state[k]))) {
        Object.assign(vehicle, state);
        saveText.textContent = 'Gespeicherte Fahrt fortgesetzt';
      }
    } else if (r.status === 401) {
      sessionToken = null; // Server lost session file or address changed.
    } else if (r.status === 404) {
      saveText.textContent = 'Neuer Spielstand';
    } else { throw new Error('Spielstand HTTP '+r.status); }
  }
  if (!sessionToken) {
    const r = await fetch('/api/session', {method: 'POST', body: ''});
    if (!r.ok) throw new Error('Neue Sitzung HTTP '+r.status);
    sessionToken = (await r.json()).token;
    try { window.localStorage.setItem('truck-browser-save-token', sessionToken); }
    catch { /* Saves still work until the browser tab closes. */ }
    saveText.textContent = 'Neuer Spielstand auf Server';
  }
  saveButton.disabled = false;
  quitButton.disabled = false;
}
async function saveGame(keepalive = false) {
  if (!sessionToken || isSaving) return;
  isSaving = true;
  try {
    const payload = JSON.stringify({x:vehicle.x,z:vehicle.z,velocity:vehicle.velocity,distance:vehicle.distance});
    const response = await fetch('/api/save', {
      method: 'POST',
      headers: {'X-Game-Session': sessionToken, 'Content-Type':'application/json'},
      body: payload, keepalive, cache: 'no-store'
    });
    if (!response.ok) throw new Error('HTTP '+response.status);
    if (!keepalive) saveText.textContent = 'Spielstand auf Server gespeichert';
  } catch (error) {
    if (!keepalive) saveText.textContent = 'Speichern fehlgeschlagen: '+error.message;
  } finally {
    isSaving = false;
    refreshNetwork();
  }
}
function updateCanvasSize() {
  const width = Math.max(2, Math.floor(canvas.clientWidth * Math.min(2, window.devicePixelRatio || 1)));
  const height = Math.max(2, Math.floor(canvas.clientHeight * Math.min(2, window.devicePixelRatio || 1)));
  if (canvas.width !== width || canvas.height !== height) {
    canvas.width = width;
    canvas.height = height;
    renderer?.resize();
  }
}

function matrixPerspective(fov, aspect, near, far) {
  const f = 1 / Math.tan(fov / 2);
  return new Float32Array([
    f / aspect, 0, 0, 0,
    0, f, 0, 0,
    0, 0, (far + near) / (near - far), -1,
    0, 0, (2 * far * near) / (near - far), 0
  ]);
}
function normalize(v) { const l = Math.hypot(...v) || 1; return v.map(n => n / l); }
function cross(a,b) { return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]; }
function dot(a,b) { return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]; }
function matrixLookAt(eye,center,up) {
  const z=normalize(eye.map((n,i)=>n-center[i]));
  const x=normalize(cross(up,z));
  const y=cross(z,x);
  return new Float32Array([
    x[0],y[0],z[0],0,
    x[1],y[1],z[1],0,
    x[2],y[2],z[2],0,
    -dot(x,eye),-dot(y,eye),-dot(z,eye),1
  ]);
}
function multiply(a,b) {
  const result=new Float32Array(16);
  for(let c=0;c<4;c++) for(let r=0;r<4;r++) {
    let value=0;
    for(let k=0;k<4;k++) value += a[k*4+r]*b[c*4+k];
    result[c*4+r]=value;
  }
  return result;
}
function createMesh(current) {
  const verts=[];
  function vertex(p,c) { verts.push(p[0],p[1],p[2],c[0],c[1],c[2]); }
  function quad(a,b,c,d,color) { vertex(a,color);vertex(b,color);vertex(c,color);vertex(a,color);vertex(c,color);vertex(d,color); }
  function cube(x,y,z,dx,dy,dz,color) {
    const x0=x-dx/2,x1=x+dx/2,y0=y,y1=y+dy,z0=z-dz/2,z1=z+dz/2;
    const face=(a,b,c,d,k)=>quad(a,b,c,d,color.map(n=>n*k));
    face([x0,y0,z0],[x1,y0,z0],[x1,y1,z0],[x0,y1,z0],0.80);
    face([x1,y0,z1],[x0,y0,z1],[x0,y1,z1],[x1,y1,z1],0.85);
    face([x0,y0,z1],[x0,y0,z0],[x0,y1,z0],[x0,y1,z1],0.68);
    face([x1,y0,z0],[x1,y0,z1],[x1,y1,z1],[x1,y1,z0],0.76);
    face([x0,y1,z0],[x1,y1,z0],[x1,y1,z1],[x0,y1,z1],1.05);
  }
  const begin = Math.floor((current.z - 90)/40)*40;
  const roadWidth=world.track.roadWidth;
  for(let s=begin;s<current.z+340;s+=40) {
    const finish=s+40;
    quad([-70,-0.10,s],[70,-0.10,s],[70,-0.10,finish],[-70,-0.10,finish],[.17,.34,.18]);
    quad([-roadWidth/2,0,s],[roadWidth/2,0,s],[roadWidth/2,0,finish],[-roadWidth/2,0,finish],[.19,.21,.25]);
    for(const edge of [-roadWidth/2+0.32,roadWidth/2-0.32])
      quad([edge-.07,.035,s],[edge+.07,.035,s],[edge+.07,.035,finish],[edge-.07,.035,finish],[.93,.95,.91]);
    for(let d=s;d<finish;d+=10)
      quad([-.10,.05,d],[.10,.05,d],[.10,.05,d+5],[-.10,.05,d+5],[.95,.90,.59]);
    const k=Math.floor(s/40);
    for(const side of [-1,1]) {
      const pos=side*(15+(k%3)*4);
      cube(pos,0,s+15,.7,4.4,.7,[.31,.22,.13]);
      cube(pos,3.6,s+15,4.2,5.0,4.3,[.08,.33+(k%3)*.04,.14]);
      if(k%2===0) {
        const hx=side*(34+(k%5)*3);
        cube(hx,0,s+20,7,5.0+(k%4),9,[.57,.47,.37]);
        cube(hx,5+(k%4),s+20,7.5,1,9.5,[.42,.20,.15]);
      }
    }
  }
  const x=current.x,z=current.z;
  cube(x,0.45,z-1.9,2.2,2.65,5.5,[.12,.48,.79]); // body
  cube(x,0.45,z+1.8,2.25,2.75,2.25,[.08,.39,.67]); // cabin
  cube(x,2.08,z+2.45,2.1,1.0,.14,[.54,.79,.92]); // windscreen
  cube(x,3.2,z-.1,2.0,.3,6.0,[.15,.53,.86]);
  for(const q of [-2.8,2.15]) for(const a of [-1.14,1.14]) cube(x+a,.19,z+q,.35,.9,1.0,[.08,.10,.12]);
  cube(x,1.1,z+3.08,1.9,.4,.08,[.86,.85,.65]);
  return new Float32Array(verts);
}

async function createWebGPURenderer() {
  if (!navigator.gpu || !window.isSecureContext) throw new Error('WebGPU not available');
  const adapter=await navigator.gpu.requestAdapter();
  if(!adapter) throw new Error('No WebGPU adapter');
  const device=await adapter.requestDevice();
  const ctx=canvas.getContext('webgpu');
  if(!ctx) throw new Error('No WebGPU canvas context');
  const format=navigator.gpu.getPreferredCanvasFormat();
  ctx.configure({device,format,alphaMode:'opaque'});
  const shader=device.createShaderModule({code:`
    struct Uniforms {viewProjection:mat4x4<f32>};
    @group(0) @binding(0) var<uniform> uniforms:Uniforms;
    struct Output {@builtin(position) position:vec4<f32>, @location(0) color:vec3<f32>};
    @vertex fn vs(@location(0) pos:vec3<f32>, @location(1) color:vec3<f32>) -> Output {
      var output:Output;
      output.position=uniforms.viewProjection*vec4<f32>(pos,1.0);
      output.color=color;
      return output;
    }
    @fragment fn fs(input:Output) -> @location(0) vec4<f32> {
      return vec4<f32>(input.color,1.0);
    }`});
  const pipeline=device.createRenderPipeline({layout:'auto',vertex:{module:shader,entryPoint:'vs',buffers:[{arrayStride:24,attributes:[{shaderLocation:0,offset:0,format:'float32x3'},{shaderLocation:1,offset:12,format:'float32x3'}]}]},fragment:{module:shader,entryPoint:'fs',targets:[{format}]},primitive:{topology:'triangle-list',cullMode:'none'},depthStencil:{format:'depth24plus',depthWriteEnabled:true,depthCompare:'less'}});
  const uniform=device.createBuffer({size:64,usage:GPUBufferUsage.UNIFORM|GPUBufferUsage.COPY_DST});
  const group=device.createBindGroup({layout:pipeline.getBindGroupLayout(0),entries:[{binding:0,resource:{buffer:uniform}}]});
  let vertexBuffer=null,vertexCapacity=0,depth=null;
  function resize() {if(depth)depth.destroy();depth=device.createTexture({size:[canvas.width,canvas.height],format:'depth24plus',usage:GPUTextureUsage.RENDER_ATTACHMENT});}
  resize();
  return {type:'WebGPU',resize,draw(mesh,vp){
    const count=mesh.length/6;
    if(mesh.byteLength>vertexCapacity){if(vertexBuffer)vertexBuffer.destroy();vertexCapacity=Math.max(mesh.byteLength,vertexCapacity*2,4096);vertexBuffer=device.createBuffer({size:vertexCapacity,usage:GPUBufferUsage.VERTEX|GPUBufferUsage.COPY_DST});}
    device.queue.writeBuffer(vertexBuffer,0,mesh);
    device.queue.writeBuffer(uniform,0,vp);
    const encoder=device.createCommandEncoder();
    const pass=encoder.beginRenderPass({colorAttachments:[{view:ctx.getCurrentTexture().createView(),clearValue:{r:.45,g:.68,b:.86,a:1},loadOp:'clear',storeOp:'store'}],depthStencilAttachment:{view:depth.createView(),depthClearValue:1,depthLoadOp:'clear',depthStoreOp:'store'}});
    pass.setPipeline(pipeline);pass.setBindGroup(0,group);pass.setVertexBuffer(0,vertexBuffer);pass.draw(count);pass.end();device.queue.submit([encoder.finish()]);
  }};
}
function compile(gl,type,source){const shader=gl.createShader(type);gl.shaderSource(shader,source);gl.compileShader(shader);if(!gl.getShaderParameter(shader,gl.COMPILE_STATUS))throw new Error(gl.getShaderInfoLog(shader));return shader;}
function createCanvas2DRenderer() {
  // Last-resort client fallback, explicitly labeled CPU (not a GPU proof).
  const ctx = canvas.getContext('2d');
  if (!ctx) throw new Error('This browser cannot open a 2D canvas');
  function project(p, m) {
    const [x,y,z] = p;
    const w = m[3]*x + m[7]*y + m[11]*z + m[15];
    if (w <= 0.1) return null;
    const sx = (m[0]*x+m[4]*y+m[8]*z+m[12])/w;
    const sy = (m[1]*x+m[5]*y+m[9]*z+m[13])/w;
    const sz = (m[2]*x+m[6]*y+m[10]*z+m[14])/w;
    if (!Number.isFinite(sx) || !Number.isFinite(sy)) return null;
    return [(sx*.5+.5)*canvas.width,(-sy*.5+.5)*canvas.height,sz];
  }
  return {type:'Canvas2D (CPU-Fallback)', resize(){},draw(mesh,viewProj) {
    ctx.fillStyle='#73aeda';ctx.fillRect(0,0,canvas.width,canvas.height);
    const triangles=[];
    for(let i=0;i<mesh.length;i+=18) {
      const p0=project(mesh.slice(i,i+3),viewProj),p1=project(mesh.slice(i+6,i+9),viewProj),p2=project(mesh.slice(i+12,i+15),viewProj);
      if (!p0||!p1||!p2) continue;
      triangles.push([p0,p1,p2,(p0[2]+p1[2]+p2[2])/3,`rgb(${Math.round(mesh[i+3]*255)},${Math.round(mesh[i+4]*255)},${Math.round(mesh[i+5]*255)})`]);
    }
    triangles.sort((a,b)=>b[3]-a[3]);
    for (const [a,b,c,depth,color] of triangles) {
      if(depth< -1||depth>1)continue;
      ctx.fillStyle=color;ctx.beginPath();ctx.moveTo(a[0],a[1]);ctx.lineTo(b[0],b[1]);ctx.lineTo(c[0],c[1]);ctx.closePath();ctx.fill();
    }
  }};
}
function createWebGLRenderer(){
  const gl=canvas.getContext('webgl2',{antialias:true});
  if(!gl)throw new Error('WebGL2 is not supported on this browser/device');
  const vertex=compile(gl,gl.VERTEX_SHADER,`#version 300 es
    layout(location=0) in vec3 pos;layout(location=1) in vec3 col;
    uniform mat4 viewProjection;out vec3 vColor;
    void main(){gl_Position=viewProjection*vec4(pos,1.0);vColor=col;}`);
  const fragment=compile(gl,gl.FRAGMENT_SHADER,`#version 300 es
    precision mediump float;in vec3 vColor;out vec4 pixel;
    void main(){pixel=vec4(vColor,1.0);}`);
  const program=gl.createProgram();gl.attachShader(program,vertex);gl.attachShader(program,fragment);gl.linkProgram(program);
  if(!gl.getProgramParameter(program,gl.LINK_STATUS))throw new Error(gl.getProgramInfoLog(program));
  const buffer=gl.createBuffer();const vao=gl.createVertexArray();gl.bindVertexArray(vao);gl.bindBuffer(gl.ARRAY_BUFFER,buffer);
  gl.vertexAttribPointer(0,3,gl.FLOAT,false,24,0);gl.enableVertexAttribArray(0);
  gl.vertexAttribPointer(1,3,gl.FLOAT,false,24,12);gl.enableVertexAttribArray(1);
  gl.enable(gl.DEPTH_TEST);
  gl.useProgram(program);
  const matrixLocation=gl.getUniformLocation(program,'viewProjection');
  return {type:'WebGL2',resize(){gl.viewport(0,0,canvas.width,canvas.height);},draw(mesh,vp){
    gl.viewport(0,0,canvas.width,canvas.height);gl.clearColor(.45,.68,.86,1);gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);
    gl.bindVertexArray(vao);gl.bindBuffer(gl.ARRAY_BUFFER,buffer);gl.bufferData(gl.ARRAY_BUFFER,mesh,gl.DYNAMIC_DRAW);
    gl.uniformMatrix4fv(matrixLocation,false,vp);gl.drawArrays(gl.TRIANGLES,0,mesh.length/6);
  }};
}
async function remoteStep(steer, gas, brake) {
  if (remotePending || !sessionToken) return;
  remotePending = true;
  try {
    const reply = await fetch('/api/remote/step', {
      method: 'POST',
      headers: {'Content-Type': 'application/json','X-Game-Session': sessionToken},
      body: JSON.stringify({steer: Math.max(-1,Math.min(1,steer)),gas:!!gas,brake:!!brake}),
      cache: 'no-store'
    });
    if (!reply.ok) throw new Error('HTTP '+reply.status);
    const state = await reply.json();
    if (!['x','z','velocity','distance'].every(k=>Number.isFinite(state[k]))) throw new Error('ungültiger Simulationszustand');
    remoteTarget = state;
    remoteReplies++;
  } catch (error) {
    remoteFailures++;
    if (remoteFailures < 4) serverText.textContent = 'Remote-Simulation unterbrochen: '+error.message;
  } finally {
    remotePending = false;
  }
}
function controls(dt){
  const pad=navigator.getGamepads?.().find(p=>p?.connected);
  const axis=pad?.axes?.[0]??0;
  const steer=(keys.has('a')||keys.has('arrowleft')||touches.left ?-1:0)+(keys.has('d')||keys.has('arrowright')||touches.right?1:0)+axis;
  const gas=keys.has('w')||keys.has('arrowup')||touches.gas||((pad?.buttons?.[7]?.value??0)>.1);
  const brake=keys.has('s')||keys.has('arrowdown')||touches.brake||((pad?.buttons?.[6]?.value??0)>.1);
  if (remoteMode) {
    const now = performance.now();
    if (now - remoteLastRequest >= 100) {
      remoteLastRequest = now;
      remoteStep(steer,gas,brake);
    }
    // Smoothly interpolate authoritative CPU-server positions using the
    // browser's own CPU/GPU; this is not video streaming or remote GPU access.
    if (remoteTarget) {
      const alpha=Math.min(1,dt*14);
      vehicle.x+=(remoteTarget.x-vehicle.x)*alpha;
      vehicle.z+=(remoteTarget.z-vehicle.z)*alpha;
      vehicle.velocity=remoteTarget.velocity;
      vehicle.distance=remoteTarget.distance;
    }
    return;
  }
  const maxSpeed=world.vehicle.maxSpeedKmh/3.6;
  vehicle.velocity=Math.max(0,Math.min(maxSpeed,vehicle.velocity+(gas?world.vehicle.acceleration*dt:0)-(brake?world.vehicle.braking*dt:0)-.4*dt));
  vehicle.x=Math.max(-world.track.roadWidth/2+1.2,Math.min(world.track.roadWidth/2-1.2,vehicle.x+steer*vehicle.velocity*.30*dt));
  vehicle.z+=vehicle.velocity*dt;
  vehicle.distance+=vehicle.velocity*dt;
  if(vehicle.z>world.track.length-50)vehicle.z=0;
}
function frame(ms){
  if(!isRunning)return;
  const dt=Math.min(.06,(ms-last)/1000 || 0);last=ms;
  controls(dt);updateCanvasSize();
  const p=matrixPerspective(Math.PI/3,canvas.width/canvas.height,.12,600);
  const v=matrixLookAt([vehicle.x*.5,5.5,vehicle.z-14],[vehicle.x*.5,1.1,vehicle.z+23],[0,1,0]);
  renderer.draw(createMesh(vehicle),multiply(p,v));
  count++;elapsed+=dt;
  speedText.textContent=Math.round(vehicle.velocity*3.6)+' km/h';
  if(elapsed>1){fpsText.textContent=Math.round(count/elapsed)+' FPS';count=0;elapsed=0;}
  requestAnimationFrame(frame);
}
async function start(){
  startButton.disabled=true;startButton.textContent='Lädt Level und Grafik …';
  try{
    const response=await fetch('/api/world',{cache:'default'});
    if(!response.ok)throw new Error('Spieldaten HTTP '+response.status);
    world=await response.json();
    if(!world.track?.roadWidth||!world.vehicle?.maxSpeedKmh)throw new Error('Leveldaten unvollständig');
    loadText.textContent='Welt geladen ('+(response.headers.get('X-Asset-Source')||'Server')+')';
    try{renderer=await createWebGPURenderer();}catch(e){console.info('WebGPU unavailable; fallback to WebGL2:',e.message);try{renderer=createWebGLRenderer();}catch(glError){console.info('WebGL2 unavailable; CPU canvas fallback:',glError.message);renderer=createCanvas2DRenderer();}}
    gpuStatus.textContent='Grafik: '+renderer.type+' auf diesem Gerät';status.textContent=renderer.type+' (lokal)';
    try { await ensureSession(); }
    catch (error) { saveText.textContent='Server-Spielstand nicht verfügbar: '+error.message; }
    remoteMode = remoteCheckbox.checked && !!sessionToken;
    remoteTarget = null;
    remoteLastRequest = 0;
    remoteFailures = 0;
    remoteReplies = 0;
    if (remoteMode) serverText.textContent='CPU-Server: 10 Zustände/s · GPU ausschließlich im Browser';
    intro.hidden=true;intro.style.display='none';canvas.focus();isRunning=true;last=performance.now();requestAnimationFrame(frame);
    refreshNetwork();
  }catch(error){console.error(error);startButton.disabled=false;startButton.textContent='Nochmal versuchen';loadText.textContent=error.message;}
}
startButton.addEventListener('click',start);
saveButton.addEventListener('click',()=>saveGame());
quitButton.addEventListener('click',async()=>{
  isRunning = false;
  await saveGame();
  intro.hidden = false; intro.style.display = 'flex';
  remoteMode = false;
  remotePending = false;
  startButton.disabled = false;
  startButton.textContent = '▶ Weiterfahren – auf diesem Gerät';
  saveButton.disabled = true; quitButton.disabled = true;
});
window.addEventListener('pagehide',()=>{
  if (isRunning && sessionToken && !isSaving) {
    // Best-effort save; the explicit save/quit buttons are more reliable.
    saveGame(true);
  }
});
setInterval(()=>{ if (isRunning) saveGame(); },30000);
setInterval(refreshNetwork,3000);
probeClient();
for(const name of ['left','right','gas','brake']){
  const el=document.getElementById(name);
  el.addEventListener('pointerdown',e=>{touches[name]=true;el.setPointerCapture(e.pointerId);});
  for(const event of ['pointerup','pointercancel','lostpointercapture'])el.addEventListener(event,()=>{touches[name]=false;});
}
window.addEventListener('keydown',e=>{const k=e.key.toLowerCase();keys.add(k);if(['arrowleft','arrowright','arrowup','arrowdown',' '].includes(k))e.preventDefault();});
window.addEventListener('keyup',e=>keys.delete(e.key.toLowerCase()));
(async()=>{try{const r=await fetch('/api/capabilities');const j=await r.json();serverText.textContent=j.server_gpu?'GPU-Server':'CPU-Server ohne GPU';}catch{serverText.textContent='Serverstatus nicht abrufbar';}})();
