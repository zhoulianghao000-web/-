package cn.pawday.pilot;

import cn.pawday.common.Api.Failure;
import java.net.URI;
import java.nio.file.*;
import java.util.*;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;

/** Fixed synthetic identities. Invitation is never authority to bypass RBAC or MFA. */
@Component
public final class PilotPolicy {
 public static final String MARKER="PAWDAY_PILOT_CONFIGURATION_BLOCKED";
 public static final String CLIENT="simulated-v1";
 public static final Set<String> PHONES;
 static {var p=new HashSet<String>();for(int i=1;i<=20;i++)p.add("+999000000"+String.format(Locale.ROOT,"%03d",i));PHONES=Set.copyOf(p);}
 private final boolean enabled;private final Path root;
 public PilotPolicy(Environment env){enabled=env.getProperty("pawday.pilot.enabled",Boolean.class,false);root=enabled?Path.of(env.getProperty("pawday.pilot.root","")).toAbsolutePath().normalize():null;}
 public boolean enabled(){return enabled;}
 public boolean paused(){return enabled&&Files.exists(root.resolve("PAUSED"));}
 public boolean allowed(String realm,String identity){return !enabled||(identity!=null&&switch(realm){case "CONSUMER"->PHONES.contains(identity);case "MERCHANT"->Set.of("local-staff-a","local-staff-b").contains(identity);case "ADMIN"->"local-admin".equals(identity);default->false;});}
 public void require(String realm,String identity){if(!allowed(realm,identity))throw new Failure(403,"PILOT_ACCOUNT_NOT_ALLOWED");if(paused())throw new Failure(503,"PILOT_PAUSED");}
 public static void validate(Environment e){
  boolean enabled=e.getProperty("pawday.pilot.enabled",Boolean.class,false);
  String mode=e.getProperty("pawday.deployment-mode","development");
  var profiles=Arrays.asList(e.getActiveProfiles());
  if(!enabled&&!"pilot".equals(mode)&&!profiles.contains("pilot"))return;
  if(!enabled||!"pilot".equals(mode)||!profiles.containsAll(List.of("local","pilot")))fail("EXPLICIT_PILOT_MODE_REQUIRED");
  try {
   var root=Path.of(e.getProperty("pawday.pilot.root",""));
   if(!root.isAbsolute()||root.normalize().getParent()==null)fail("DEDICATED_ABSOLUTE_ROOT_REQUIRED");
   root=root.normalize();
   for(String key:List.of("pawday.storage.local-root","pawday.auth.local-sms-directory")){
    var child=Path.of(e.getProperty(key,"")).toAbsolutePath().normalize();
    if(!child.startsWith(root)||child.equals(root))fail("LOCAL_DATA_OUTSIDE_PILOT_ROOT");
   }
   String jdbc=e.getProperty("spring.datasource.url","");
   var db=URI.create(jdbc.replaceFirst("^jdbc:",""));
   if(!jdbc.startsWith("jdbc:postgresql:")||!loopback(db.getHost())||db.getUserInfo()!=null||db.getQuery()!=null||db.getFragment()!=null||!db.getPath().matches("/pawday_pilot_[a-z0-9_]+"))fail("DEDICATED_LOOPBACK_DATABASE_REQUIRED");
   var search=URI.create(e.getProperty("pawday.search.url",""));
   if(!"http".equals(search.getScheme())||!loopback(search.getHost())||search.getUserInfo()!=null||search.getQuery()!=null||search.getFragment()!=null)fail("LOOPBACK_SEARCH_REQUIRED");
   for(String key:List.of("spring.data.redis.host","spring.rabbitmq.host"))if(!loopback(e.getProperty(key,"")))fail("LOOPBACK_INFRASTRUCTURE_REQUIRED");
   for(String key:List.of("pawday.payment.simulation-enabled","pawday.settlement.simulation-enabled","pawday.auth.local-sms-enabled"))if(!e.getProperty(key,Boolean.class,false))fail("SIMULATION_REQUIRED");
   if(!e.getProperty("pawday.ai.deepseek-api-key","").isBlank()||e.getProperty("pawday.ai.allow-loopback-provider",Boolean.class,false)||e.getProperty("pawday.privacy.export-enabled",Boolean.class,false))fail("EXTERNAL_CREDENTIAL_OR_EXPORT_FORBIDDEN");
   if(e.getProperty("pawday.nearby.navigation-enabled",Boolean.class,true))fail("NAVIGATION_MUST_BE_DISABLED");
  } catch(IllegalStateException ex){throw ex;} catch(Exception ex){fail("INVALID_PILOT_CONFIGURATION");}
 }
 private static boolean loopback(String s){return s!=null&&Set.of("localhost","127.0.0.1","[::1]","::1").contains(s);}
 private static void fail(String reason){throw new IllegalStateException(MARKER+": "+reason);}
}
