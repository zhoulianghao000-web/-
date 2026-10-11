package cn.pawday.pilot;
import cn.pawday.ai.ExplanationProvider;
import java.util.*;
import org.springframework.stereotype.Component;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
/** Deterministic local evidence selection, never an HTTP or cloud inference. */
@Component
@ConditionalOnProperty(name="pawday.pilot.enabled",havingValue="true")
public final class PilotExplanationProvider implements ExplanationProvider {
 public boolean available(){return true;}
 public Plan explain(String instruction,List<Map<String,Object>> evidence){return new Plan(evidence.stream().map(e->e.get("id").toString()).distinct().limit(12).toList());}
}
