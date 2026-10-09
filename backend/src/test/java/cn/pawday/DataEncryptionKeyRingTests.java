package cn.pawday;

import cn.pawday.identity.*;
import cn.pawday.operations.ScrapeCredential;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.util.Base64;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import static org.junit.jupiter.api.Assertions.*;

class DataEncryptionKeyRingTests {
    static final byte[] LEGACY=new byte[32],CLEAR="TEST_ONLY_PRIVATE_DATA".getBytes(StandardCharsets.UTF_8);
    static String key(int n){byte[] b=new byte[32];java.util.Arrays.fill(b,(byte)n);return Base64.getEncoder().encodeToString(b);}
    DataEncryptionKeyRing ring(String active){return new DataEncryptionKeyRing(active,"old:"+key(1)+",new:"+key(2));}
    @Test void legacyCiphertextRemainsReadableAfterRotation(){var old=new DataEncryptionKeyRing("legacy","");String cipher=old.encrypt(CLEAR,LEGACY);assertFalse(cipher.contains(":"));assertArrayEquals(CLEAR,ring("new").decrypt(cipher,LEGACY));}
    @Test void newWritesUseOnlyActiveKeyAndReadBothVersions(){String old=ring("old").encrypt(CLEAR,LEGACY),current=ring("new").encrypt(CLEAR,LEGACY);assertTrue(current.startsWith("pd1:new:"));assertArrayEquals(CLEAR,ring("new").decrypt(old,LEGACY));assertArrayEquals(CLEAR,ring("old").decrypt(current,LEGACY));}
    @Test void rollbackRetainsReadabilityAndDoesNotChangeHmac(){var a=new Crypto(key(0),Clock.systemUTC(),ring("old"));var b=new Crypto(key(0),Clock.systemUTC(),ring("new"));assertEquals(a.otpHash("id","123456"),b.otpHash("id","123456"));assertArrayEquals(CLEAR,a.decrypt(b.encrypt(CLEAR)));}
    @Test void keyIdentityIsAuthenticated(){String cipher=ring("old").encrypt(CLEAR,LEGACY);assertThrows(IllegalStateException.class,()->ring("new").decrypt(cipher.replace("pd1:old:","pd1:new:"),LEGACY));}
    @Test void ciphertextTamperAndTruncationFailWithoutEcho(){String cipher=ring("new").encrypt(CLEAR,LEGACY);String bad=cipher.substring(0,cipher.length()-8);var e=assertThrows(IllegalStateException.class,()->ring("new").decrypt(bad,LEGACY));assertEquals("DATA_DECRYPTION_FAILED",e.getMessage());assertNull(e.getCause());}
    @Test void missingOldKeyRefusesRead(){String cipher=ring("old").encrypt(CLEAR,LEGACY);var noOld=new DataEncryptionKeyRing("new","new:"+key(2));assertFalse(noOld.canRead(cipher));assertThrows(IllegalStateException.class,()->noOld.decrypt(cipher,LEGACY));}
    @Test void differentNoncesPreventRepeatedCiphertext(){assertNotEquals(ring("new").encrypt(CLEAR,LEGACY),ring("new").encrypt(CLEAR,LEGACY));}
    @Test void cannotReuseAuthKeyAsDataKey(){var ring=new DataEncryptionKeyRing("active","active:"+key(0));assertThrows(IllegalStateException.class,()->ring.encrypt(CLEAR,LEGACY));}
    @Test void authKeyReuseIsRejectedAtCryptoConstruction(){var e=assertThrows(IllegalArgumentException.class,()->new Crypto(key(0),Clock.systemUTC(),new DataEncryptionKeyRing("legacy","inactive:"+key(0))));assertEquals("AUTH_AND_DATA_KEYS_MUST_DIFFER",e.getMessage());}
    @ParameterizedTest @ValueSource(strings={"bad","old:bad","legacy:AAAA","old:AAAA,old:AAAA","SECRET_IN_ID!:AAAA","old:"})
    void invalidKeysDoNotLeakInput(String config){var e=assertThrows(IllegalArgumentException.class,()->new DataEncryptionKeyRing("old",config));assertEquals("INVALID_DATA_KEY_RING",e.getMessage());assertNull(e.getCause());}
    @Test void unknownActiveKeyCannotFallBack(){assertThrows(IllegalArgumentException.class,()->new DataEncryptionKeyRing("missing","old:"+key(1)));}
    @Test void disabledScrapeCredentialAcceptsNothing(){assertFalse(new ScrapeCredential("").accepts("/actuator/prometheus","Bearer test"));}
    @Test void machineCredentialHasOneExactEndpoint(){String token="TEST_ONLY_"+"X".repeat(40);var c=new ScrapeCredential(token);assertTrue(c.accepts("/actuator/prometheus","Bearer "+token));for(String path:java.util.List.of("/actuator/metrics","/api/v1/admin/outbox","/actuator/prometheus/","/actuator/prometheus/../metrics"))assertFalse(c.accepts(path,"Bearer "+token));assertFalse(c.accepts("/actuator/prometheus","Bearer wrong"));}
    @Test void invalidScrapeSecretDoesNotLeak(){var e=assertThrows(IllegalArgumentException.class,()->new ScrapeCredential("TEST_PRIVATE_INVALID"));assertEquals("INVALID_METRICS_CREDENTIAL",e.getMessage());}
}
