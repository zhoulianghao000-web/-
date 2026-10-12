package cn.pawday.search;
import cn.pawday.common.Api;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;
import org.springframework.web.bind.annotation.*;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
@RestController @ConditionalOnProperty(name="pawday.search.enabled",havingValue="true",matchIfMissing=true)
public class ConsumerSearchController {
 private final ProductSearchService search;public ConsumerSearchController(ProductSearchService search){this.search=search;}
 @GetMapping({"/api/v1/public/products","/api/v1/consumer/products"})Object list(@RequestParam Map<String,String> params,HttpServletRequest r){var f=new HashMap<>(params);String cursor=f.remove("cursor"),raw=f.remove("limit");int limit=20;try{if(raw!=null)limit=Integer.parseInt(raw);}catch(Exception bad){throw new Api.Failure(400,"VALIDATION_ERROR");}return search.list(ProductSearchFilter.parse(f),cursor,limit,Api.meta(r));}
 @GetMapping("/api/v1/public/products/facets")Object facets(HttpServletRequest r){return Api.ok(search.facets(),r);}
}
