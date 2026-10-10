package cn.pawday.privacy;

import java.nio.channels.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.io.IOException;
import java.util.*;
import tools.jackson.databind.json.JsonMapper;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/** Development independent filesystem adapter. Exclusive OS lock, immutable
 * checkpoints, forced bytes and atomic pointer. No fallback to non-atomic moves.
 * Production replication, WORM/KMS and trusted latest-head custody remain pending.
 */
public final class LocalPrivacyExportProvider implements PrivacyExportProvider {
    private final Path root;private final byte[] key;private final JsonMapper json=JsonMapper.builder().build();
    public LocalPrivacyExportProvider(Path root,byte[] key){this.root=root.toAbsolutePath().normalize();this.key=key.clone();if(key.length<32)throw new IllegalArgumentException("PRIVACY_KEY_REQUIRED");}
    private void safe(Path path)throws IOException {
        for(Path p=path;p!=null;p=p.getParent())if(Files.isSymbolicLink(p))throw new IOException("UNSAFE_EXPORT_PATH");
    }
    private Map<String,Object> validate(byte[] envelope)throws IOException {
        if(envelope.length>1500000)throw new IOException("OVERSIZE_CHECKPOINT");
        try {
            var e=json.readTree(envelope);byte[] data=Base64.getDecoder().decode(e.get("payload").asString());String signature=e.get("signature").asString();
            if(!java.security.MessageDigest.isEqual(signature.getBytes(StandardCharsets.US_ASCII),PrivacyExportService.sign(data,key).getBytes(StandardCharsets.US_ASCII)))throw new IOException("INVALID_CHECKPOINT_SIGNATURE");
            var p=json.readTree(data);
            return Map.of("sequence",p.get("last_sequence").asLong(),"covered",java.time.Instant.parse(p.get("covered_until").asString()),"journal",p.get("journal_id").asString(),"system",p.get("system_id").asString(),"events",p.get("events"));
        }catch(RuntimeException invalid){throw new IOException("INVALID_CHECKPOINT");}
    }
    private void forceWrite(Path path,byte[] data)throws IOException {
        try(var channel=FileChannel.open(path,StandardOpenOption.CREATE_NEW,StandardOpenOption.WRITE)){var bytes=java.nio.ByteBuffer.wrap(data);while(bytes.hasRemaining())channel.write(bytes);channel.force(true);}
    }
    private void forceDirectory()throws IOException {
        // Linux supports directory fsync; Windows atomic replacement is verified
        // separately but this adapter makes no power-loss promise on Windows.
        if(!System.getProperty("os.name").startsWith("Windows"))try(var directory=FileChannel.open(root,StandardOpenOption.READ)){directory.force(true);}
    }
    @Override public void publish(PrivacyExportService.Checkpoint checkpoint) {
        if(TransactionSynchronizationManager.isActualTransactionActive())throw new IllegalStateException("EXPORT_IO_IN_TRANSACTION");
        try {
            safe(root);Files.createDirectories(root);safe(root);
            Path lockPath=root.resolve(".publish.lock"),latest=root.resolve("latest.json");safe(lockPath);safe(latest);
            // A second JVM waits; a second thread may receive an overlapping-lock
            // failure and follows the same durable retry path.
            try(var channel=FileChannel.open(lockPath,StandardOpenOption.CREATE,StandardOpenOption.WRITE);var lock=channel.lock()) {
                byte[] envelope=json.writeValueAsString(Map.of("payload",Base64.getEncoder().encodeToString(checkpoint.payload()),"signature",checkpoint.signature())).getBytes(StandardCharsets.UTF_8);
                var incoming=validate(envelope);
                if(Files.exists(latest)) {
                    var old=validate(Files.readAllBytes(latest));
                    if(!old.get("journal").equals(incoming.get("journal"))||!old.get("system").equals(incoming.get("system")))throw new IOException("EXPORT_ORIGIN_CONFLICT");
                    long previous=(Long)old.get("sequence"),next=(Long)incoming.get("sequence");
                    var a=(tools.jackson.databind.JsonNode)old.get("events");var b=(tools.jackson.databind.JsonNode)incoming.get("events");
                    for(int i=0;i<Math.min(previous,next);i++)if(!a.get(i).equals(b.get(i)))throw new IOException("EXPORT_PREFIX_CONFLICT");
                    if(previous>next||((java.time.Instant)old.get("covered")).isAfter((java.time.Instant)incoming.get("covered")))return;
                }
                Path immutable=root.resolve(checkpoint.sha256()+".json");safe(immutable);
                if(Files.exists(immutable)) {if(!Arrays.equals(Files.readAllBytes(immutable),envelope))throw new IOException("CHECKPOINT_CONFLICT");}
                else {Path staging=root.resolve(".checkpoint-"+UUID.randomUUID());try{forceWrite(staging,envelope);Files.move(staging,immutable,StandardCopyOption.ATOMIC_MOVE);forceDirectory();}finally{Files.deleteIfExists(staging);}}
                Path staging=root.resolve(".latest-"+UUID.randomUUID());try{forceWrite(staging,envelope);Files.move(staging,latest,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);forceDirectory();}finally{Files.deleteIfExists(staging);}
            }
        }catch(IOException|RuntimeException e){throw new IllegalStateException("INDEPENDENT_EXPORT_UNAVAILABLE");}
    }
}
