package cn.pawday.ai;
import java.util.*;
/** Produces an evidence-selection plan only. No authority, SQL, URLs or business tools. */
public interface ExplanationProvider {
 record Plan(List<String> evidenceIds){}
 Plan explain(String instruction,List<Map<String,Object>> evidence);
 boolean available();
}
