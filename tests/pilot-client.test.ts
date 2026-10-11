import {describe,it,expect} from 'vitest';
import {PawdayClient} from '../packages/api-client/src';
describe('pilot client contract',()=>{
 it('marks login and rejects an ordinary backend before accepting tokens',async()=>{
  let marker:string|null=null;
  const client=new PawdayClient('merchant','http://localhost/api/v1',async input=>{marker=(input as Request).headers.get('X-Pawday-Pilot');return new Response('{}',{headers:{'Content-Type':'application/json'}});},()=>{},true);
  await expect(client.staffLogin({login_name:'local-staff-a',password:'TEST_ONLY',device_id:'TEST'})).rejects.toMatchObject({code:'PILOT_ENVIRONMENT_MISMATCH'});expect(marker).toBe('simulated-v1');expect(client.authenticated).toBe(false);
 });
 it('marks authenticated public reads with bearer and pilot contract',async()=>{
  let request:Request|undefined;
  const client=new PawdayClient('merchant','http://localhost/api/v1',async input=>{request=input as Request;return new Response(JSON.stringify({data:[],meta:{request_id:'r',correlation_id:'r'}}),{headers:{'Content-Type':'application/json','X-Pawday-Environment':'SIMULATED_PILOT'}});},()=>{},true);
  client.setSession({access_token:'TEST_ACCESS',refresh_token:'TEST_REFRESH',expires_in:900,session_id:'TEST_SESSION',user_id:null});
  await client.api.GET('/public/pet-taxonomy');expect(request?.headers.get('Authorization')).toBe('Bearer TEST_ACCESS');expect(request?.headers.get('X-Pawday-Pilot')).toBe('simulated-v1');
 });
});
