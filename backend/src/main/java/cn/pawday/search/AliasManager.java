package cn.pawday.search;
import java.util.*;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;
@Component @ConditionalOnProperty(name="pawday.search.enabled",havingValue="true",matchIfMissing=true)
public class AliasManager {
    private final OpenSearchClient client;public AliasManager(OpenSearchClient client){this.client=client;}
    public String target(String alias) {
        if(!Set.of(IndexVersion.READ_ALIAS,IndexVersion.WRITE_ALIAS).contains(alias))throw new IllegalArgumentException("Invalid alias");
        var data=client.request("GET","/_alias/"+alias,null,404);
        if(data.containsKey("error"))return null;
        if(data.size()!=1)throw new OpenSearchClient.Unavailable("SEARCH_ALIAS_INCONSISTENT");
        return OpenSearchClient.index(data.keySet().iterator().next());
    }
    public String current() {
        String read=target(IndexVersion.READ_ALIAS),write=target(IndexVersion.WRITE_ALIAS);
        if(!Objects.equals(read,write))throw new OpenSearchClient.Unavailable("SEARCH_ALIAS_INCONSISTENT");return read;
    }
    public void switchTo(String target) {
        OpenSearchClient.index(target);String current=current();if(target.equals(current))return;
        var actions=new ArrayList<Map<String,Object>>();
        if(current!=null){actions.add(Map.of("remove",Map.of("index",current,"alias",IndexVersion.READ_ALIAS)));actions.add(Map.of("remove",Map.of("index",current,"alias",IndexVersion.WRITE_ALIAS)));}
        actions.add(Map.of("add",Map.of("index",target,"alias",IndexVersion.READ_ALIAS,"filter",Map.of("term",Map.of("deleted",false)))));
        actions.add(Map.of("add",Map.of("index",target,"alias",IndexVersion.WRITE_ALIAS,"is_write_index",true)));
        client.request("POST","/_aliases",Map.of("actions",actions));
        if(!target.equals(current()))throw new OpenSearchClient.Unavailable("SEARCH_ALIAS_SWITCH_UNCONFIRMED");
    }
}
