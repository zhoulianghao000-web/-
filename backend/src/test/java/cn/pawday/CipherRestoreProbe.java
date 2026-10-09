package cn.pawday;
import cn.pawday.identity.DataEncryptionKeyRing;
import java.util.*;

/** Synthetic restore gate only. Receives test ciphertexts over stdin, never logs them. */
public final class CipherRestoreProbe {
    private static String key(int n){byte[] b=new byte[32];Arrays.fill(b,(byte)n);return Base64.getEncoder().encodeToString(b);}
    public static void main(String[] args)throws Exception {
        var keys=new DataEncryptionKeyRing("new","old:"+key(1)+",new:"+key(2));
        var rows=new java.io.BufferedReader(new java.io.InputStreamReader(System.in)).lines().toList();
        if(rows.size()!=3)throw new IllegalStateException("FIXTURE_INCOMPLETE");
        for(String row:rows)if(!Arrays.equals(new byte[20],keys.decrypt(row,new byte[32])))throw new IllegalStateException("RESTORE_DECRYPTION_FAILED");
        try {new DataEncryptionKeyRing("new","new:"+key(2)).decrypt(rows.get(1),new byte[32]);throw new IllegalStateException("MISSING_KEY_NOT_REJECTED");}
        catch(IllegalStateException expected){if(!expected.getMessage().equals("DATA_DECRYPTION_FAILED"))throw expected;}
        System.out.println("{\"result\":\"PASS\",\"versions\":3,\"missing_key_rejected\":true}");
    }
}
