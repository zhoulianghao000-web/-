package cn.pawday.support;
import java.util.UUID;
/** Future low-risk FAQ/order-state assistant seam. V1 routes to a human; no AI authority or implementation. */
public interface SupportAssistant {
 record Suggestion(String text,boolean humanRequired){}
 Suggestion suggest(UUID conversationId,UUID authorizedPrincipalId);
}
