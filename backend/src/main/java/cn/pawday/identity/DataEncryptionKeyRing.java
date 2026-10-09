package cn.pawday.identity;

import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.*;
import javax.crypto.Cipher;
import javax.crypto.spec.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/** Versioned data keys. Auth/HMAC remains on its existing key; legacy data stays readable. */
@Component
public final class DataEncryptionKeyRing {
    private final Map<String,byte[]> keys;
    private final String active;
    private final SecureRandom random=new SecureRandom();
    public DataEncryptionKeyRing(@Value("${pawday.data-encryption.active-key-id:legacy}") String active,
            @Value("${pawday.data-encryption.keys:}") String encodedKeys) {
        try {
            var parsed=new HashMap<String,byte[]>();
            if(!encodedKeys.isEmpty()) for(String entry:encodedKeys.split(",",-1)) {
                String[] pair=entry.split(":",2);
                if(pair.length!=2 || !pair[0].matches("[a-z][a-z0-9_-]{0,31}") || pair[0].equals("legacy")) throw new IllegalArgumentException();
                byte[] key=Base64.getDecoder().decode(pair[1]);
                if(key.length!=32 || parsed.putIfAbsent(pair[0],key)!=null) throw new IllegalArgumentException();
            }
            if(!active.equals("legacy") && !parsed.containsKey(active)) throw new IllegalArgumentException();
            this.active=active;this.keys=Map.copyOf(parsed);
        } catch(Exception invalid) {throw new IllegalArgumentException("INVALID_DATA_KEY_RING");}
    }
    public String encrypt(byte[] clear,byte[] legacy) {
        try {
            byte[] key=active.equals("legacy")?legacy:keys.get(active);
            if(!active.equals("legacy") && java.security.MessageDigest.isEqual(key,legacy)) throw new IllegalStateException();
            byte[] nonce=new byte[12];random.nextBytes(nonce);
            var c=Cipher.getInstance("AES/GCM/NoPadding");c.init(Cipher.ENCRYPT_MODE,new SecretKeySpec(key,"AES"),new GCMParameterSpec(128,nonce));
            if(!active.equals("legacy")) c.updateAAD(("pawday-data:"+active).getBytes(StandardCharsets.UTF_8));
            byte[] cipher=c.doFinal(clear),all=new byte[12+cipher.length];System.arraycopy(nonce,0,all,0,12);System.arraycopy(cipher,0,all,12,cipher.length);
            return (active.equals("legacy")?"":"pd1:"+active+":")+Base64.getEncoder().encodeToString(all);
        } catch(Exception invalid) {throw new IllegalStateException("DATA_ENCRYPTION_UNAVAILABLE");}
    }
    public void requireSeparateFrom(byte[] authKey) {
        for(byte[] key:keys.values()) if(java.security.MessageDigest.isEqual(key,authKey))
            throw new IllegalArgumentException("AUTH_AND_DATA_KEYS_MUST_DIFFER");
    }
    public byte[] decrypt(String encoded,byte[] legacy) {
        try {
            String id=null,body=encoded;
            if(encoded.startsWith("pd1:")) {String[] parts=encoded.split(":",-1);if(parts.length!=3 || !keys.containsKey(parts[1]))throw new IllegalArgumentException();id=parts[1];body=parts[2];}
            byte[] all=Base64.getDecoder().decode(body);if(all.length<28)throw new IllegalArgumentException();
            var c=Cipher.getInstance("AES/GCM/NoPadding");c.init(Cipher.DECRYPT_MODE,new SecretKeySpec(id==null?legacy:keys.get(id),"AES"),new GCMParameterSpec(128,all,0,12));
            if(id!=null)c.updateAAD(("pawday-data:"+id).getBytes(StandardCharsets.UTF_8));
            return c.doFinal(all,12,all.length-12);
        } catch(Exception invalid) {throw new IllegalStateException("DATA_DECRYPTION_FAILED");}
    }
    public boolean canRead(String encoded) {
        if(encoded==null)return true;
        if(!encoded.startsWith("pd1:"))return !encoded.contains(":");
        String[] parts=encoded.split(":",-1);return parts.length==3 && keys.containsKey(parts[1]);
    }
}
