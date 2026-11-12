"""Blender batch preparation. Run with --factory-startup --disable-autoexec."""
import bpy
from pathlib import Path
import json,zipfile,sys,math,shutil
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT/'third_party'/'slice-v040'
SRC.mkdir(exist_ok=True)
DOWNLOAD=ROOT/'downloads'/'slice-v040'
DEST=ROOT/'game'/'assets'/'slice'
DEST.mkdir(exist_ok=True)
with zipfile.ZipFile(DOWNLOAD/'smallarms.zip') as z:
    if not (SRC/'m4.blend').exists():(SRC/'m4.blend').write_bytes(z.read('m4.blend'))

def load(path):
    bpy.ops.wm.open_mainfile(filepath=str(path),load_ui=False,use_scripts=False)

def inspect():
    result={}
    for name,path in [('gun',SRC/'m4.blend'),('rocks',DOWNLOAD/'rock_moss_set_01_1k.blend'),('crate',DOWNLOAD/'old_military_crate_1k.blend')]:
        load(path)
        result[name]=[{'name':o.name,'type':o.type,'dimensions':list(o.dimensions),'location':list(o.location),'polygons':len(o.data.polygons) if o.type=='MESH' else 0} for o in bpy.context.scene.objects]
    (ROOT/'docs'/'slice-v040-model-inspection.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print('ASSET_INSPECTION',json.dumps(result)[:11000])

def material(name,asset):
    mat=bpy.data.materials.new(name);mat.use_nodes=True
    nodes=mat.node_tree.nodes;links=mat.node_tree.links;p=nodes.get('Principled BSDF')
    p.inputs['Roughness'].default_value=.8
    for suffix,channel in [('diff','Base Color'),('rough','Roughness'),('nor_gl','Normal')]:
        file=DOWNLOAD/(asset+'_'+suffix+'_1k.jpg')
        if not file.exists():continue
        tex=nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(file),check_existing=True)
        if suffix!='diff':tex.image.colorspace_settings.name='Non-Color'
        if suffix=='nor_gl':
            norm=nodes.new('ShaderNodeNormalMap');links.new(tex.outputs['Color'],norm.inputs['Color']);links.new(norm.outputs['Normal'],p.inputs[channel])
        else:links.new(tex.outputs['Color'],p.inputs[channel])
    return mat

def export(objects,name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.export_scene.gltf(filepath=str(DEST/name),export_format='GLB',use_selection=True,export_animations=False,export_yup=True,export_apply=True)

def convert():
    with zipfile.ZipFile(DOWNLOAD/'Ground015_1K-JPG.zip') as z:
        for suffix,target in [('Color.jpg','ground_color.jpg'),('NormalGL.jpg','ground_normal.jpg'),('Roughness.jpg','ground_rough.jpg')]:
            matches=[n for n in z.namelist() if n.endswith(suffix)]
            if not matches:raise ValueError('Ground channel missing '+suffix)
            (DEST/target).write_bytes(z.read(matches[0]))
    output=[]
    load(DOWNLOAD/'rock_moss_set_01_1k.blend')
    mat=material('Scanned moss and stone','rock_moss_set_01')
    for i,o in enumerate(sorted([o for o in bpy.context.scene.objects if o.type=='MESH'],key=lambda o:o.name)):
        o.data.materials.clear();o.data.materials.append(mat)
        for p in o.data.polygons:p.use_smooth=True
        d=o.modifiers.new('Vega8 simplified scan','DECIMATE');d.ratio=min(1.0,1800/max(len(o.data.polygons),1))
        export([o],f'rock_{i}.glb');output.append({'file':f'rock_{i}.glb','source_polygons':len(o.data.polygons),'decimate_ratio':d.ratio})
    load(DOWNLOAD/'old_military_crate_1k.blend')
    mat=material('Worn military crate','old_military_crate')
    objs=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.name.endswith('_a')]
    for o in objs:o.data.materials.clear();o.data.materials.append(mat)
    export(objs,'crate.glb')
    load(SRC/'m4.blend')
    o=next(o for o in bpy.context.scene.objects if o.type=='MESH')
    coords=[o.matrix_world@v.co for v in o.data.vertices]
    low=Vector(tuple(min(v[k] for v in coords) for k in range(3)))
    high=Vector(tuple(max(v[k] for v in coords) for k in range(3)))
    center=(low+high)/2;length=high.x-low.x
    def thickness(end):
        band=[v for v in coords if (v.x<low.x+length*.08 if end==0 else v.x>high.x-length*.08)]
        return max(v.z for v in band)-min(v.z for v in band)
    barrel_positive=thickness(1)<thickness(0)
    angle=math.pi/2 if barrel_positive else -math.pi/2
    turn=Matrix.Rotation(angle,4,'Z')
    for v,p in zip(o.data.vertices,coords):v.co=turn@((p-center)*(.86/length))
    o.matrix_world=Matrix.Identity(4)
    o.name='YS04_receiver'
    # Blender 2.x materials are converted to modern PBR, keeping part colours.
    for slot_index,slot in enumerate(o.material_slots):
        old=slot.material
        color=tuple(old.diffuse_color[:3]) if old else (.18,.19,.18)
        m=bpy.data.materials.new('YS04_'+(old.name if old else 'steel'));m.use_nodes=True
        bs=m.node_tree.nodes.get('Principled BSDF')
        brightness=sum(color)/3
        col=[(.045,.052,.045,1),(.11,.12,.105,1),(.08,.09,.09,1)][slot_index%3]
        bs.inputs['Base Color'].default_value=col
        bs.inputs['Metallic'].default_value=.35 if slot_index==0 else .65
        bs.inputs['Roughness'].default_value=.62 if slot_index==0 else .44
        slot.material=m
    if not o.material_slots:
        m=bpy.data.materials.new('YS04_steel');m.use_nodes=True
        bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(.16,.18,.17,1);bs.inputs['Metallic'].default_value=.75;bs.inputs['Roughness'].default_value=.42;o.data.materials.append(m)
    parts=json.loads((ROOT/'docs/slice-v040-gun-parts.json').read_text(encoding='utf-8'))
    magazine_ids=set(min(parts,key=lambda p:p['bounds'][0][2])['indices'])
    source=o.data;materials=list(source.materials)
    def part_mesh(keep,name):
        ids=sorted(keep);remap={old:new for new,old in enumerate(ids)}
        faces=[p for p in source.polygons if all(i in keep for i in p.vertices)]
        mesh=bpy.data.meshes.new(name);mesh.from_pydata([source.vertices[i].co[:] for i in ids],[],[[remap[i] for i in p.vertices] for p in faces]);mesh.update()
        for mat in materials:mesh.materials.append(mat)
        for new,old in zip(mesh.polygons,faces):new.material_index=old.material_index
        return mesh
    mag=bpy.data.objects.new('YS04_magazine',part_mesh(magazine_ids,'Detachable magazine'))
    bpy.context.collection.objects.link(mag)
    o.data=part_mesh(set(range(len(source.vertices)))-magazine_ids,'Rifle receiver')
    for part in [o,mag]:
        bevel=part.modifiers.new('Machined edge highlights','BEVEL');bevel.width=.0018;bevel.segments=2
    export([o,mag],'rifle.glb')
    output.append({'file':'rifle.glb','author':'Tabasco','source':'https://opengameart.org/node/3609','source_polygons':len(source.polygons),'receiver_polygons':len(o.data.polygons),'magazine_polygons':len(mag.data.polygons),'barrel_positive_x':barrel_positive,'modified':'Normalized axes and scale; converted part materials to PBR; bevelled edges; separated magazine for local reload animation; no original animations exported'})
    (ROOT/'docs'/'slice-v040-conversion.json').write_text(json.dumps(output,indent=2),encoding='utf-8')
    print('SLICE_ASSETS_EXPORTED',json.dumps(output))

def gun_parts():
    load(SRC/'m4.blend')
    o=next(o for o in bpy.context.scene.objects if o.type=='MESH')
    parent=list(range(len(o.data.vertices)))
    def find(i):
        while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
        return i
    for e in o.data.edges:parent[find(e.vertices[0])]=find(e.vertices[1])
    groups={}
    for v in o.data.vertices:groups.setdefault(find(v.index),[]).append(v.index)
    result=[]
    for ids in sorted(groups.values(),key=len,reverse=True):
        vs=[o.matrix_world@o.data.vertices[i].co for i in ids]
        lo=[min(v[k] for v in vs) for k in range(3)];hi=[max(v[k] for v in vs) for k in range(3)]
        result.append(dict(count=len(ids),indices=ids,bounds=[lo,hi]))
    (ROOT/'docs/slice-v040-gun-parts.json').write_text(json.dumps(result),encoding='utf-8')
    print('GUN_PARTS',json.dumps([{k:v for k,v in r.items() if k!='indices'} for r in result])[:13000])

if '--gun-parts' in sys.argv:
    gun_parts()
elif '--inspect' in sys.argv:
    inspect()
elif '--convert' in sys.argv:
    convert()
