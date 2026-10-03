package cn.pawday.identity;

import java.time.Clock;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.charset.StandardCharsets;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.core.env.Environment;

@Configuration
public class AuthInfrastructure {
    @Bean Clock authClock() { return Clock.systemUTC(); }
    @Bean PasswordEncoder passwordEncoder() { return new BCryptPasswordEncoder(12); }
    @Bean public SmsGateway smsGateway(Environment env) {
        boolean local=java.util.Arrays.asList(env.getActiveProfiles()).contains("local");
        boolean production=java.util.Arrays.asList(env.getActiveProfiles()).contains("production");
        boolean enabled=env.getProperty("pawday.auth.local-sms-enabled",Boolean.class,false);
        if(local && !production && enabled) {
            Path inbox=Path.of(env.getProperty("pawday.auth.local-sms-directory",".local-sms"));
            return (id,phone,code)-> {
                try { Files.createDirectories(inbox);Files.writeString(inbox.resolve(id+".txt"),phone+"\n"+code+"\n",StandardCharsets.UTF_8,java.nio.file.StandardOpenOption.CREATE_NEW); }
                catch(java.nio.file.FileAlreadyExistsException alreadyDelivered) { /* Stable idempotency key: success on duplicate. */ }
                catch(java.io.IOException ex) { throw new cn.pawday.common.Api.Failure(503,"SMS_DELIVERY_UNAVAILABLE"); }
            };
        }
        return (id,phone,code)-> { throw new cn.pawday.common.Api.Failure(503,"SMS_PROVIDER_NOT_CONFIGURED"); };
    }
}
