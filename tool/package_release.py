"""Package portable source and an optional self-contained compiled web release."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import argparse, hashlib, json

root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,default=root.parent);args=p.parse_args();args.output.mkdir(parents=True,exist_ok=True)
excluded={'.git','.idea','.dart_tool','.cache','.gradle','.swiftpm','Pods','node_modules','build','coverage','web_release','artifacts','ephemeral','.symlinks','__pycache__'}
files_excluded={'local.properties','Generated.xcconfig','flutter_export_environment.sh','GeneratedPluginRegistrant.java','GeneratedPluginRegistrant.h','GeneratedPluginRegistrant.m','.flutter-plugins-dependencies','.DS_Store'}

def include(path):
 rel=path.relative_to(root)
 return not any(part in excluded for part in rel.parts) and path.name not in files_excluded and path.suffix not in {'.iml','.ipr','.iws','.pyc','.zip'} and not(path.suffix=='.log' and not rel.as_posix().startswith('docs/qa/'))

source=args.output/'Invita_Studio_Flutter_Source.zip'
with ZipFile(source,'w',ZIP_DEFLATED,compresslevel=6) as z:
 for file in sorted(root.rglob('*')):
  if file.is_file() and include(file):z.write(file,Path('invitation_studio')/file.relative_to(root))
 assert z.testzip() is None
 count=len(z.infolist())
print(f'{source.name}: {count} files, {source.stat().st_size:,} bytes')

packages=[source]
webroot=root/'web_release'
if (webroot/'main.dart.js').exists():
 web=args.output/'Invita_Studio_Web.zip'
 with ZipFile(web,'w',ZIP_DEFLATED,compresslevel=6) as z:
  for file in sorted(webroot.rglob('*')):
   if file.is_file():z.write(file,Path('Invita_Studio_Web')/file.relative_to(webroot))
  assert z.testzip() is None
  count=len(z.infolist())
 print(f'{web.name}: {count} files, {web.stat().st_size:,} bytes')
 packages.append(web)
manifest={file.name:{'bytes':file.stat().st_size,'sha256':hashlib.sha256(file.read_bytes()).hexdigest()} for file in packages}
(args.output/'Invita_Studio_Packages.json').write_text(json.dumps(manifest,indent=2)+'\n')
