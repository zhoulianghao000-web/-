// Deliberately small OpenAPI subset generator. Unsupported schema kinds fail the gate.
export function generateDart(doc,hash) {
  const schemas=doc.components.schemas;
  function info(schema) {
    if(schema.anyOf){const nonNull=schema.anyOf.filter(x=>x.type!=='null');if(nonNull.length!==1)throw new Error('Unsupported Dart union');return info(nonNull[0]);}
    if(schema.$ref)return {type:schema.$ref.split('/').pop(),read:x=>`${schema.$ref.split('/').pop()}.fromJson(Map<String,dynamic>.from(${x} as Map))`,write:x=>`${x}.toJson()`};
    const kind=Array.isArray(schema.type)?schema.type.find(x=>x!=='null'):schema.type;
    if(kind==='array'){const item=info(schema.items);return {type:`List<${item.type}>`,read:x=>`(${x} as List).map((value) => ${item.read('value')}).toList()`,write:x=>`${x}.map((value) => ${item.write('value')}).toList()`};}
    const type={string:'String',integer:'int',number:'double',boolean:'bool',object:'Map<String,dynamic>'}[kind];
    if(!type)throw new Error(`Unsupported Dart schema ${JSON.stringify(schema)}`);
    return {type,read:x=>kind==='integer'?`(${x} as num).toInt()`:kind==='number'?`(${x} as num).toDouble()`:kind==='object'?`Map<String,dynamic>.from(${x} as Map)`:`${x} as ${type}`,write:x=>x};
  }
  let output=`// Generated from Pawday runtime OpenAPI; SHA256 ${hash}\n// ignore_for_file: non_constant_identifier_names, constant_identifier_names, use_null_aware_elements, prefer_null_aware_operators\n\n`;
  for(const [name,schema] of Object.entries(schemas)){
    if(schema.type!=='object'||!schema.properties)throw new Error(`Unsupported root schema ${name}`);
    const fields=Object.entries(schema.properties).map(([key,s])=>({key,...info(s),required:(schema.required??[]).includes(key),nullable:!(schema.required??[]).includes(key)||(Array.isArray(s.type)&&s.type.includes('null'))||s.anyOf?.some(x=>x.type==='null')}));
    const ctor=fields.length===0?`const ${name}();`:`const ${name}({${fields.map(f=>`${f.required?'required ':''}this.${f.key}`).join(', ')}});`;
    output+=`class ${name} {\n${fields.map(f=>`  final ${f.type}${f.nullable?'?':''} ${f.key};`).join('\n')}\n  ${ctor}\n  factory ${name}.fromJson(Map<String,dynamic> json) => ${name}(\n${fields.map(f=>`    ${f.key}: ${f.nullable?`json['${f.key}'] == null ? null : `:''}${f.read(`json['${f.key}']`)},`).join('\n')}\n  );\n  Map<String,dynamic> toJson() => {\n${fields.map(f=>`    ${f.nullable&&!f.required?`if (${f.key} != null) `:''}'${f.key}': ${f.nullable?`${f.key} == null ? null : ${f.write(f.key+'!')}`:f.write(f.key)},`).join('\n')}\n  };\n}\n\n`;
  }
  output+='class ApiRoutes {\n';
  for(const [path,methods] of Object.entries(doc.paths))for(const op of Object.values(methods)){if(!op.operationId)continue;output+=`  static const ${op.operationId} = '${path}';\n`;}
  return output+'}\n';
}
