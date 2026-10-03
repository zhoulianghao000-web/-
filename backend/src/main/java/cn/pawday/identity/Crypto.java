package cn.pawday.identity;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Clock;
import java.util.Base64;
import java.util.HexFormat;
import javax.crypto.Cipher;
import javax.crypto.Mac;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class Crypto {
    private final SecureRandom random=new SecureRandom();
    private final byte[] key;
    private final Clock clock;
    public Crypto(@Value("${pawday.auth.secret-key}") String encoded,Clock clock) {
        this.key=Base64.getDecoder().decode(encoded); this.clock=clock;
        if(key.length!=32) throw new IllegalArgumentException("PAWDAY_AUTH_SECRET must be 32 bytes in base64");
    }
    public String token() { byte[] b=new byte[32];random.nextBytes(b);return Base64.getUrlEncoder().withoutPadding().encodeToString(b); }
    public String otp() { return "%06d".formatted(random.nextInt(1000000)); }
    public String hash(String value) {
        try { return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8))); }
        catch(Exception e) { throw new IllegalStateException("hash unavailable",e); }
    }
    public String otpHash(String id,String code) {
        try { var m=Mac.getInstance("HmacSHA256");m.init(new SecretKeySpec(key,"HmacSHA256"));return HexFormat.of().formatHex(m.doFinal((id+":"+code).getBytes(StandardCharsets.UTF_8))); }
        catch(Exception e) { throw new IllegalStateException("HMAC unavailable",e); }
    }
    public boolean equal(String a,String b) { return a!=null && b!=null && MessageDigest.isEqual(a.getBytes(StandardCharsets.UTF_8),b.getBytes(StandardCharsets.UTF_8)); }
    public String encrypt(byte[] secret) {
        try { byte[] nonce=new byte[12];random.nextBytes(nonce);var c=Cipher.getInstance("AES/GCM/NoPadding");c.init(Cipher.ENCRYPT_MODE,new SecretKeySpec(key,"AES"),new GCMParameterSpec(128,nonce));byte[] ciphertext=c.doFinal(secret);byte[] out=new byte[nonce.length+ciphertext.length];System.arraycopy(nonce,0,out,0,12);System.arraycopy(ciphertext,0,out,12,ciphertext.length);return Base64.getEncoder().encodeToString(out); }
        catch(Exception e) { throw new IllegalStateException("encryption unavailable",e); }
    }
    public byte[] decrypt(String encoded) {
        try { byte[] b=Base64.getDecoder().decode(encoded);var c=Cipher.getInstance("AES/GCM/NoPadding");c.init(Cipher.DECRYPT_MODE,new SecretKeySpec(key,"AES"),new GCMParameterSpec(128,b,0,12));return c.doFinal(b,12,b.length-12); }
        catch(Exception e) { throw new IllegalStateException("invalid MFA configuration"); }
    }
    public String totp(byte[] secret,long step) {
        try {var m=Mac.getInstance("HmacSHA1");m.init(new SecretKeySpec(secret,"HmacSHA1"));byte[] out=m.doFinal(java.nio.ByteBuffer.allocate(8).putLong(step).array());int offset=out[out.length-1]&15;int binary=((out[offset]&127)<<24)|((out[offset+1]&255)<<16)|((out[offset+2]&255)<<8)|(out[offset+3]&255);return "%06d".formatted(binary%1000000);}
        catch(Exception e) {throw new IllegalStateException("TOTP unavailable",e);}
    }
    public long matchTotp(String encrypted,String code) {
        if(encrypted==null || code==null || !code.matches("[0-9]{6}")) return -1;
        byte[] secret=decrypt(encrypted); long current=clock.instant().getEpochSecond()/30;
        for(long step=current+1;step>=current-1;step--) if(equal(totp(secret,step),code)) return step;
        return -1;
    }
}
