return async function(tools, repo, ref, selectedIds, previewOnly) {
  const lookup="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  function from64(src){
    src=src.replace(/\s+/g,""); const tab=new Uint8Array(128);
    for(let i=0;i<64;i++)tab[lookup.charCodeAt(i)]=i;
    const n=Math.floor(src.length*3/4)-(src.endsWith("==")?2:src.endsWith("=")?1:0);
    const out=new Uint8Array(n);let j=0;
    for(let i=0;i<src.length;i+=4){
      const val=(tab[src.charCodeAt(i)]<<18)|(tab[src.charCodeAt(i+1)]<<12)
        |((src[i+2]=="="?0:tab[src.charCodeAt(i+2)])<<6)
        |(src[i+3]=="="?0:tab[src.charCodeAt(i+3)]);
      out[j++]=(val>>>16)&255;if(j<n)out[j++]=(val>>>8)&255;if(j<n)out[j++]=val&255;
    }
    return out;
  }
  function to64(src) {
    let out="";
    for(let i=0;i<src.length;i+=3){
      const a=src[i],b=i+1<src.length?src[i+1]:0,c=i+2<src.length?src[i+2]:0;
      const v=(a<<16)|(b<<8)|c;
      out+=lookup[(v>>>18)&63]+lookup[(v>>>12)&63]+
        (i+1<src.length?lookup[(v>>>6)&63]:"=")+(i+2<src.length?lookup[v&63]:"=");
    }
    return out;
  }
  function read32(arr,i){return ((arr[i]*16777216)+(arr[i+1]<<16)+(arr[i+2]<<8)+arr[i+3])>>>0;}
  function write32(arr,i,v){arr[i]=(v>>>24)&255;arr[i+1]=(v>>>16)&255;arr[i+2]=(v>>>8)&255;arr[i+3]=v&255;}
  function inflate(z) {
    let at=2,bits=0,buf=0;
    function read(n){while(bits<n){if(at>=z.length)throw Error("Truncated deflate");buf|=z[at++]<<bits;bits+=8;}
      const v=buf&((1<<n)-1);buf>>>=n;bits-=n;return v;}
    function tree(lengths){
      const max=Math.max(...lengths),count=Array(max+1).fill(0),next=Array(max+1).fill(0),map=new Map();
      for(const n of lengths)if(n)count[n]++;
      let code=0;for(let n=1;n<=max;n++){code=(code+(count[n-1]||0))<<1;next[n]=code;}
      for(let n=0;n<lengths.length;n++){
        const len=lengths[n];if(!len)continue;let c=next[len]++,rev=0;
        for(let j=0;j<len;j++){rev=(rev<<1)|(c&1);c>>=1;}map.set((len<<16)|rev,n);
      }
      return {max,map};
    }
    function sym(t){let c=0;for(let n=1;n<=t.max;n++){c|=read(1)<<(n-1);
      const v=t.map.get((n<<16)|c);if(v!==undefined)return v;}
      throw Error("Invalid Huffman symbol");}
    const lb=[3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258];
    const le=[0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0];
    const db=[1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577];
    const de=[0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13];
    const order=[16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15];
    const out=[];
    while(true){
      const last=read(1),mode=read(2);
      if(mode===0){const rem=bits%8;if(rem)read(rem);
        const len=read(16);read(16);for(let i=0;i<len;i++)out.push(read(8));}
      else {
        let lt,dt;
        if(mode===1) {
          lt=tree(Array.from({length:288},(_,i)=>i<144?8:i<256?9:i<280?7:8));
          dt=tree(Array(32).fill(5));
        } else if(mode===2) {
          const nl=read(5)+257,nd=read(5)+1,nc=read(4)+4;
          const cl=Array(19).fill(0);for(let i=0;i<nc;i++)cl[order[i]]=read(3);
          const ct=tree(cl),lengths=[];
          while(lengths.length<nl+nd){
            const s=sym(ct);
            if(s<16)lengths.push(s);
            else if(s===16){const prev=lengths[lengths.length-1];for(let i=read(2)+3;i>0;i--)lengths.push(prev);}
            else if(s===17){for(let i=read(3)+3;i>0;i--)lengths.push(0);}
            else {for(let i=read(7)+11;i>0;i--)lengths.push(0);}
          }
          lt=tree(lengths.slice(0,nl));dt=tree(lengths.slice(nl,nl+nd));
        } else throw Error("Invalid DEFLATE block");
        while(true) {
          const s=sym(lt);if(s<256){out.push(s);continue;}if(s===256)break;
          const k=s-257; if(k<0||k>28)throw Error("Bad length");
          const n=lb[k]+read(le[k]),d=sym(dt),dist=db[d]+read(de[d]);
          for(let i=0;i<n;i++)out.push(out[out.length-dist]);
        }
      }
      if(last)break;
    }
    return Uint8Array.from(out);
  }
  function decodePNG(b64) {
    const b=from64(b64),idats=[];let at=8,bytes=0,w=0,h=0,channels=4,depth=8;
    while(at<b.length){
      const n=read32(b,at),name=String.fromCharCode(...b.slice(at+4,at+8)),d=b.slice(at+8,at+8+n);
      at+=n+12;
      if(name==="IHDR"){w=read32(d,0);h=read32(d,4);depth=d[8];channels=d[9]===6?4:0;}
      if(name==="IDAT"){bytes+=n;idats.push(d);}
      if(name==="IEND")break;
    }
    if(depth!==8||channels!==4)throw Error("Expected RGBA8 source atlas");
    const z=new Uint8Array(bytes);let pos=0;
    for(const d of idats){z.set(d,pos);pos+=d.length;}
    const raw=inflate(z),stride=w*4,pixels=new Uint8Array(w*h*4);
    let r=0,j=0;let last=new Uint8Array(stride);
    for(let y=0;y<h;y++){
      const filter=raw[r++];
      for(let x=0;x<stride;x++){
        const v=raw[r++],a=x>=4?pixels[j-4]:0,b=last[x],c=x>=4?last[x-4]:0;
        let pred=0;
        if(filter===1)pred=a;
        else if(filter===2)pred=b;
        else if(filter===3)pred=(a+b)>>1;
        else if(filter===4){const p=a+b-c,pa=Math.abs(p-a),pb=Math.abs(p-b),pc=Math.abs(p-c);pred=pa<=pb&&pa<=pc?a:pb<=pc?b:c;}
        pixels[j++]=(v+pred)&255;
      }
      last=pixels.slice(j-stride,j);
    }
    return {width:w,height:h,pixels};
  }
  const crcTable=new Uint32Array(256);
  for(let i=0;i<256;i++){let c=i;for(let j=0;j<8;j++)c=c&1?(0xedb88320^(c>>>1)):(c>>>1);crcTable[i]=c>>>0;}
  function crc(bytes){let c=0xffffffff;for(const n of bytes)c=crcTable[(c^n)&255]^(c>>>8);return (c^0xffffffff)>>>0;}
  function concat(parts) {let n=0;for(const p of parts)n+=p.length;const result=new Uint8Array(n);let pos=0;
    for(const p of parts){result.set(p,pos);pos+=p.length;}return result;}
  function chunk(name,data){
    const out=new Uint8Array(12+data.length);
    write32(out,0,data.length);
    for(let i=0;i<4;i++)out[4+i]=name.charCodeAt(i);
    out.set(data,8);
    write32(out,8+data.length,crc(out.slice(4,8+data.length)));
    return out;
  }
  function encodePNG(w,h,pixels) {
    const stride=w*4,raw=new Uint8Array((stride+1)*h);
    for(let y=0;y<h;y++)raw.set(pixels.subarray(y*stride,(y+1)*stride),y*(stride+1)+1);
    const blocks=[new Uint8Array([0x78,0x01])];
    let a=1,b=0;
    for(let i=0;i<raw.length;i++){a=(a+raw[i])%65521;b=(b+a)%65521;}
    for(let i=0;i<raw.length;i+=65535){
      const n=Math.min(65535,raw.length-i),block=new Uint8Array(n+5);
      block[0]=i+n>=raw.length?1:0;
      block[1]=n&255;block[2]=n>>>8;
      block[3]=(~n)&255;block[4]=((~n)>>>8)&255;
      block.set(raw.subarray(i,i+n),5);blocks.push(block);
    }
    const adler=new Uint8Array(4);write32(adler,0,((b<<16)|a)>>>0);blocks.push(adler);
    const header=new Uint8Array(13);write32(header,0,w);write32(header,4,h);header[8]=8;header[9]=6;
    return concat([new Uint8Array([137,80,78,71,13,10,26,10]),chunk("IHDR",header),
      chunk("IDAT",concat(blocks)),chunk("IEND",new Uint8Array(0))]);
  }
  // 32 cumulative frames: six foundation passes, fifteen frame/plank/brick
  // passes, nine tile/thatch passes, and a final zero-loss authored source.
  // Each segment is drawn from the approved original source pixels only.
  function revealStep(x,y,w,h,a){
    const nx=x/Math.max(1,w),ny=y/Math.max(1,h);
    const base=a.foundation_start,roof=a.roof_end;
    if(ny>=base){
      const row=Math.max(0,Math.floor((h-1-y)/Math.max(2,a.brick_height)));
      const col=Math.floor((x + (row%2?Math.floor(a.brick_width/2):0))/a.brick_width);
      const totalRows=Math.ceil((1-base)*h/a.brick_height);
      const cols=Math.ceil(w/a.brick_width)+1;
      const progress=(row*cols+col)/(Math.max(1,totalRows*cols));
      return Math.min(6,1+Math.floor(progress*6));
    }
    if(ny>=roof){
      const closeToPost=a.posts.some(v=>Math.abs(nx-v)<Math.max(.014,2/w));
      if(closeToPost)return 7+Math.floor((base-ny)/(base-roof)*3);
      const row=Math.max(0,Math.floor((base*h-y)/a.brick_height));
      const offset=row%2===0?0:Math.floor(a.brick_width/2);
      const col=Math.floor((x+offset)/a.brick_width);
      const rows=Math.max(1,Math.ceil((base-roof)*h/a.brick_height));
      const cols=Math.max(1,Math.ceil(w/a.brick_width)+1);
      const progress=Math.max(0,Math.min(.999,(row*cols+col)/(rows*cols)));
      return 9+Math.floor(progress*13);
    }
    // Sculpted roof order: individual thatch/tile pixel clusters are exposed
    // in diagonally-staggered courses, with distinct pitch per building.
    const row=Math.max(0,Math.floor((roof*h-y)/a.tile_height));
    const stagger=row%2===0?0:Math.floor(a.tile_width/2);
    const col=Math.floor((x+stagger)/a.tile_width);
    const rows=Math.max(1,Math.ceil(roof*h/a.tile_height));
    const cols=Math.max(1,Math.ceil(w/a.tile_width)+1);
    const order=Math.max(0,Math.min(.999,(row*cols+col)/(rows*cols)));
    return 22+Math.floor(order*9);
  }
  function buildSheet(atlas,rect,layout) {
    const [left,top,w,h]=rect,columns=8,rows=4,frames=32;
    const width=w*columns,height=h*rows,out=new Uint8Array(width*height*4);
    const mask=new Uint8Array(w*h),source=new Uint8Array(w*h*4);
    let count=0;
    for(let y=0;y<h;y++)for(let x=0;x<w;x++){
      const src=((top+y)*atlas.width+left+x)*4,dest=(y*w+x)*4;
      source.set(atlas.pixels.subarray(src,src+4),dest);
      if(source[dest+3]>0){mask[y*w+x]=revealStep(x,y,w,h,layout);count++;}
    }
    for(let frame=1;frame<frames;frame++){
      const ox=(frame%columns)*w,oy=Math.floor(frame/columns)*h;
      for(let y=0;y<h;y++)for(let x=0;x<w;x++){
        const src=(y*w+x)*4;if(mask[y*w+x]===0||mask[y*w+x]>frame)continue;
        const dest=((oy+y)*width+ox+x)*4;
        out.set(source.subarray(src,src+4),dest);
      }
    }
    // Exact pixel identity of the last frame; keep a zero-loss checksum.
    for(let i=0;i<w*h;i++){
      const src=i*4,x=i%w,y=Math.floor(i/w);
      const dest=(((rows-1)*h+y)*width+(columns-1)*w+x)*4;
      out.set(source.subarray(src,src+4),dest);
    }
    return {w:width,h:height,pixels:out,pieces:count};
  }
  const fetch=async path=>(await tools.mcp__GitHub__fetch_file(
    {repository_full_name:repo,path,ref,encoding:path.endsWith(".png")?"base64":"utf-8"})).result.content;
  const [layoutJSON,catJSON,atlasJSON]=await Promise.all([
    fetch("data/architecture/hand_authored_piece_layouts.json"),
    fetch("data/buildings/catalogue.json"),fetch("assets/pixel/atlas.json")]);
  const layouts=JSON.parse(layoutJSON).layouts,buildings=JSON.parse(catJSON).buildings;
  const atlasMeta=JSON.parse(atlasJSON);
  const originals=await Promise.all(["assets/pixel/sprite_atlas.png",
    "assets/pixel/architecture_early.png"].map(fetch));
  const atlasPages=originals.map(decodePNG);
  const result=[];
  for(const building of buildings){
    const id=building.id;if(selectedIds?.length&&!selectedIds.includes(id))continue;
    const layout=layouts[id],sprite=building.visual.sprite,entry=atlasMeta[sprite];
    if(!layout||!entry)throw Error("Missing hand-authored artwork blueprint "+id);
    const page=atlasPages[entry.page||0],rect=entry.packed_rect;
    const image=buildSheet(page,rect,layout);
    const encoded=encodePNG(image.w,image.h,image.pixels);
    const encoded64=to64(encoded);
    if(previewOnly)result.push({id,base64:encoded64,pieces:image.pieces,width:image.w,height:image.h});
    else {
      const b=await tools.mcp__GitHub__create_blob({repository_full_name:repo,content:encoded64,encoding:"base64"});
      result.push({path:"assets/pixel/construction_frames/"+id+".png",mode:"100644",type:"blob",
        sha:b.result.sha,id,pieces:image.pieces,bytes:encoded.length});
    }
  }
  return result;
}