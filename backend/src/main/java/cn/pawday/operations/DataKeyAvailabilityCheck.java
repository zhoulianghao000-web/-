package cn.pawday.operations;

import cn.pawday.identity.DataEncryptionKeyRing;
import org.springframework.beans.factory.InitializingBean;
import org.springframework.boot.sql.init.dependency.DependsOnDatabaseInitialization;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

/** Refuse retirement of any data key still referenced in the current database. */
@Component @DependsOnDatabaseInitialization
public final class DataKeyAvailabilityCheck implements InitializingBean {
    private final JdbcTemplate db;private final DataEncryptionKeyRing keys;
    public DataKeyAvailabilityCheck(JdbcTemplate db,DataEncryptionKeyRing keys){this.db=db;this.keys=keys;}
    @Override public void afterPropertiesSet() {
        for(String column:java.util.List.of("identity_principal.mfa_secret_ciphertext","otp_challenge.delivery_secret_ciphertext",
                "ai_messages.user_text_ciphertext","ai_messages.result_ciphertext")) {
            String[] pair=column.split("\\.");
            for(String id:db.queryForList("SELECT DISTINCT split_part("+pair[1]+",':',2) FROM "+pair[0]+" WHERE "+pair[1]+" LIKE 'pd1:%'",String.class))
                if(!keys.canRead("pd1:"+id+":"))throw new IllegalStateException("DATA_KEY_STILL_REQUIRED");
        }
    }
}
