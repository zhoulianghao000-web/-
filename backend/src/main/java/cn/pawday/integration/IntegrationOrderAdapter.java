package cn.pawday.integration;

import java.util.UUID;

/** Internal adapter only. No controller accepts an instruction, result or provider URL. */
interface IntegrationOrderAdapter {
 record Instruction(UUID connection,UUID merchant,String businessKey,String payloadSha256){}
 record Observation(String result,UUID connection,UUID merchant,String businessKey,String payloadSha256,
                    String reference,boolean noExternalOrder){}
 Observation query(Instruction instruction);
 Observation submit(Instruction instruction);
}
