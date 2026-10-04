package cn.pawday.search;

import java.net.URI;
import java.net.URLEncoder;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;
import tools.jackson.databind.json.JsonMapper;

/** Small vendor-independent HTTP adapter. All calls have bounded deadlines. */
@Component @ConditionalOnProperty(name="pawday.search.enabled",havingValue="true",matchIfMissing=true)
public class OpenSearchClient {
    public static class Unavailable extends RuntimeException {
        public final String code; public Unavailable(String code){super(code);this.code=code;}
    }
    private final URI base; private final HttpClient http; private final Duration timeout;
    private final String authorization; private final JsonMapper json=JsonMapper.builder().build();
    public OpenSearchClient(@Value("${pawday.search.url:http://localhost:9200}") String url,
        @Value("${pawday.search.timeout-ms:3000}") long timeoutMs,
        @Value("${pawday.search.username:}") String user,@Value("${pawday.search.password:}") String password) {
        base=URI.create(url.replaceAll("/$",""));
        if(!Set.of("http","https").contains(base.getScheme()) || base.getHost()==null || base.getUserInfo()!=null || (base.getPath()!=null&&!base.getPath().isEmpty()))throw new IllegalArgumentException("Invalid OpenSearch endpoint");
        if(timeoutMs<100 || timeoutMs>60000)throw new IllegalArgumentException("Invalid search timeout");
        timeout=Duration.ofMillis(timeoutMs);http=HttpClient.newBuilder().connectTimeout(timeout).build();
        authorization=user.isBlank()?null:"Basic "+Base64.getEncoder().encodeToString((user+":"+password).getBytes(StandardCharsets.UTF_8));
    }
    @SuppressWarnings("unchecked") public Map<String,Object> request(String method,String path,Object body,int... allowed) {
        try {
            var builder=HttpRequest.newBuilder(URI.create(base+path)).timeout(timeout).header("Content-Type","application/json");
            if(authorization!=null)builder.header("Authorization",authorization);
            builder.method(method,body==null?HttpRequest.BodyPublishers.noBody():HttpRequest.BodyPublishers.ofString(json.writeValueAsString(body)));
            var response=http.send(builder.build(),HttpResponse.BodyHandlers.ofString());
            boolean accepted=response.statusCode()>=200&&response.statusCode()<300;
            for(int code:allowed)accepted|=response.statusCode()==code;
            if(!accepted)throw new Unavailable(response.statusCode()==409?"SEARCH_VERSION_CONFLICT":"SEARCH_HTTP_"+response.statusCode());
            if(response.body().isBlank())return Map.of();
            return json.readValue(response.body(),Map.class);
        }catch(Unavailable e){throw e;}catch(InterruptedException e){Thread.currentThread().interrupt();throw new Unavailable("SEARCH_INTERRUPTED");}
        catch(Exception e){throw new Unavailable("SEARCH_UNAVAILABLE");}
    }
    public Map<String,Object> health(){return request("GET","/_cluster/health",null);}
    public static String index(String index) {
        if(index==null || !index.matches("pawday-product-v1-[a-z0-9-]{6,64}"))throw new IllegalArgumentException("Invalid controlled search index");return index;
    }
    public void put(String index,UUID id,long revision,Map<String,Object> document) {
        request("PUT","/"+index(index)+"/_doc/"+id+"?version="+revision+"&version_type=external_gte",document,409);
        // 409 means another worker already applied a newer PostgreSQL revision.
    }
    public void refresh(String index){request("POST","/"+index(index)+"/_refresh",null);}
    @SuppressWarnings("unchecked") public Map<UUID,Map<String,Object>> documents(String index) {
        var all=new LinkedHashMap<UUID,Map<String,Object>>(); String scroll=null;
        try {
            var page=request("POST","/"+index(index)+"/_search?scroll=1m",Map.of("size",500,"query",Map.of("match_all",Map.of()),"sort",List.of("_doc")));
            for(;;) {
                scroll=(String)page.get("_scroll_id"); var hits=(Map<String,Object>)page.get("hits");var items=(List<Map<String,Object>>)hits.get("hits");
                if(items.isEmpty())break;
                for(var hit:items)all.put(UUID.fromString(hit.get("_id").toString()),(Map<String,Object>)hit.get("_source"));
                if(scroll==null)break;
                page=request("POST","/_search/scroll",Map.of("scroll","1m","scroll_id",scroll));
            }
        } finally {if(scroll!=null)try{request("DELETE","/_search/scroll",Map.of("scroll_id",List.of(scroll)),404);}catch(Unavailable ignored){}}
        return all;
    }
}
