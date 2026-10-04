package cn.pawday.common;

import cn.pawday.common.Api.Failure;
import cn.pawday.identity.Actor;
import cn.pawday.identity.Crypto;
import java.util.*;
import java.util.function.Supplier;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionTemplate;
import tools.jackson.databind.json.JsonMapper;

/** Shared PostgreSQL command boundary; callers enforce their domain authorization first. */
@Component
public class IdempotentCommandExecutor {
 private final JdbcTemplate db;
 private final TransactionTemplate tx;
 private final Crypto crypto;
 private final JsonMapper json=JsonMapper.builder().build();

 public IdempotentCommandExecutor(JdbcTemplate db,TransactionTemplate tx,Crypto crypto){
  this.db=db;this.tx=tx;this.crypto=crypto;
 }

 public Map<String,Object> command(Actor actor,String action,String key,Object payload,Supplier<Map<String,Object>> work){
  if(key==null||key.length()<16||key.length()>128)throw new Failure(400,"IDEMPOTENCY_KEY_REQUIRED");
  String hash=crypto.hash(json.writeValueAsString(canonical(payload)));
  return tx.execute(s->{
   db.queryForList("SELECT pg_advisory_xact_lock(hashtextextended(?,0))",actor.principalId()+":"+action+":"+key);
   var prior=db.queryForList("SELECT payload_hash,result_json FROM identity_command WHERE principal_id=? AND action=? AND idempotency_key=?",actor.principalId(),action,key);
   if(!prior.isEmpty()){
    if(!hash.equals(prior.getFirst().get("payload_hash")))throw new Failure(409,"IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD");
    return json.readValue(prior.getFirst().get("result_json").toString(),Map.class);
   }
   var result=work.get();
   db.update("INSERT INTO identity_command(principal_id,action,idempotency_key,payload_hash,result_json) VALUES (?,?,?,?,?::jsonb)",actor.principalId(),action,key,hash,json.writeValueAsString(result));
   return result;
  });
 }

 private Object canonical(Object value){
  if(value instanceof Map<?,?> map){Map<String,Object> sorted=new TreeMap<>();map.forEach((k,v)->sorted.put(k.toString(),canonical(v)));return sorted;}
  if(value instanceof List<?> values)return values.stream().map(this::canonical).toList();
  return value;
 }
}
