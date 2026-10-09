"""Hash-verified offline dump/media bundle. Never includes encryption key values.

Use only after quiescing writes and obtaining a consistent database/media snapshot.
This is not WAL/PITR, production backup scheduling, or a production restore command.
"""
from pathlib import Path
import datetime, hashlib, json, re, shutil

class BundleError(ValueError):
    pass

def digest(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda:f.read(1024*1024),b''): h.update(block)
    return h.hexdigest()

def safe_file(root, name):
    root=Path(root).absolute()
    if not isinstance(name,str) or not re.fullmatch(r'(database\.dump|media/[0-9a-f-]{36}\.(png|jpg|mp4))',name): raise BundleError('INVALID_BUNDLE_PATH')
    path=root/name
    if not path.is_file() or path.resolve()!=path.absolute() or root.resolve()!=root: raise BundleError('UNSAFE_BUNDLE_PATH')
    for p in [path,*path.parents]:
        if p.is_symlink(): raise BundleError('UNSAFE_BUNDLE_PATH')
    if path.stat().st_nlink!=1: raise BundleError('UNSAFE_BUNDLE_LINK')
    return path

def verify_bundle(root, expected_commit):
    root=Path(root).absolute(); manifest=root/'manifest.json'
    if manifest.is_symlink() or manifest.stat().st_size>1024*1024: raise BundleError('INVALID_BUNDLE_MANIFEST')
    m=json.loads(manifest.read_text(encoding='utf8'))
    if set(m)!={'schema_version','source_commit','created_at','key_references','files','quiesced'} or m['schema_version']!='pawday-offline-bundle/v1' or m['source_commit']!=expected_commit or not re.fullmatch('[0-9a-f]{40}',expected_commit) or m['quiesced'] is not True: raise BundleError('INVALID_BUNDLE_MANIFEST')
    refs=m['key_references']
    if not isinstance(refs,list) or not refs or len(refs)!=len(set(refs)) or any(not re.fullmatch('secrets://pawday/(production|test-only)/[a-z0-9_-]+',r) for r in refs): raise BundleError('INVALID_KEY_REFERENCES')
    created=datetime.datetime.fromisoformat(m['created_at'])
    if created.utcoffset() is None or created>datetime.datetime.now(datetime.timezone.utc): raise BundleError('INVALID_BUNDLE_TIME')
    files=m['files']
    if not isinstance(files,dict) or not 1<=len(files)<=10000 or 'database.dump' not in files: raise BundleError('INVALID_BUNDLE_FILES')
    actual={p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file()}
    if actual!=set(files)|{'manifest.json'}: raise BundleError('UNEXPECTED_BUNDLE_FILE')
    for name,expected in files.items():
        p=safe_file(root,name)
        if set(expected)!={'size','sha256'} or type(expected['size']) is not int or not 0<expected['size']<=2*1024**3 or not re.fullmatch('[0-9a-f]{64}',expected['sha256']): raise BundleError('INVALID_FILE_RECORD')
        if p.stat().st_size!=expected['size'] or digest(p)!=expected['sha256']: raise BundleError('BUNDLE_HASH_MISMATCH')
    return m

def create_bundle(dump,media,output,commit,key_references,*,quiesced=False):
    if not quiesced: raise BundleError('QUIESCENCE_REQUIRED')
    output=Path(output).absolute()
    if output.exists() or output.is_symlink(): raise BundleError('BUNDLE_TARGET_EXISTS')
    if output.resolve()!=output: raise BundleError('UNSAFE_BUNDLE_TARGET')
    dump=Path(dump);media=Path(media).absolute()
    if dump.is_symlink() or not dump.is_file() or dump.stat().st_nlink!=1 or dump.resolve()!=dump.absolute(): raise BundleError('UNSAFE_DUMP')
    # Validate all source objects before creating the destination.
    originals=[]
    for p in media.rglob('*'):
        if p.is_symlink(): raise BundleError('UNSAFE_MEDIA_PATH')
        if p.is_file(): originals.append((p,safe_file(media,p.relative_to(media).as_posix())))
    output.mkdir(parents=True)
    shutil.copyfile(dump,output/'database.dump')
    for p,_ in originals:
        target=output/p.relative_to(media);target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,target)
    files={p.relative_to(output).as_posix():{'size':p.stat().st_size,'sha256':digest(p)} for p in output.rglob('*') if p.is_file()}
    m={'schema_version':'pawday-offline-bundle/v1','source_commit':commit,'created_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'key_references':key_references,'files':files,'quiesced':True}
    (output/'manifest.json').write_text(json.dumps(m,indent=2)+'\n',encoding='utf8')
    verify_bundle(output,commit)
    return m
