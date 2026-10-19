const fs=require('fs'),path=require('path');
(async()=>{
 const Parser=require('../.tools/node_modules/web-tree-sitter');
 await Parser.init();
 const language=await Parser.Language.load(path.resolve(__dirname,'../.tools/node_modules/tree-sitter-wasms/out/tree-sitter-swift.wasm'));
 const parser=new Parser(); parser.setLanguage(language);
 const files=[];
 function visit(dir){for(const name of fs.readdirSync(dir)){const p=path.join(dir,name);if(fs.statSync(p).isDirectory())visit(p);else if(p.endsWith('.swift'))files.push(p);}}
 visit(path.resolve(__dirname,'../AppifyWebiOS'));visit(path.resolve(__dirname,'../Tests'));
 let errors=0;
 for(const file of files){const tree=parser.parse(fs.readFileSync(file,'utf8')); if(tree.rootNode.hasError()){console.log(path.relative(process.cwd(),file)); function bad(node){if(node.type==='ERROR'||node.isMissing()){console.log(node.startPosition,JSON.stringify(node.text.slice(0,180)));errors++;}for(const child of node.children)bad(child);}bad(tree.rootNode);}}
 console.log(`${files.length} Swift files parsed; ${errors} syntax errors`);process.exitCode=errors?1:0;
})().catch(e=>{console.error(e);process.exitCode=1;});
