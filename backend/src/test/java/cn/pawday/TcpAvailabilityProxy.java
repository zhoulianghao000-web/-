package cn.pawday;

import java.io.IOException;
import java.net.*;
import java.util.Set;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;

/** Fault injection in front of an actual Redis/OpenSearch TCP service; no protocol or data simulation. */
public final class TcpAvailabilityProxy implements AutoCloseable {
    private final ServerSocket server;
    private final String targetHost;private final int targetPort;
    private final Set<Socket> sockets=ConcurrentHashMap.newKeySet();
    private final AtomicBoolean available=new AtomicBoolean(true),closed=new AtomicBoolean(false);
    private final ExecutorService workers=Executors.newCachedThreadPool(r->{Thread t=new Thread(r,"real-infra-tcp-proxy");t.setDaemon(true);return t;});
    public TcpAvailabilityProxy(String host,int port) throws IOException {
        targetHost=host;targetPort=port;server=new ServerSocket(0,50,InetAddress.getLoopbackAddress());
        workers.submit(()->{while(!closed.get())try{Socket client=server.accept();if(!available.get()){client.close();continue;}workers.submit(()->forward(client));}catch(IOException ignored){if(!closed.get())unavailable();}});
    }
    public int port(){return server.getLocalPort();}
    public void unavailable(){available.set(false);for(Socket s:sockets)closeSocket(s);sockets.clear();}
    public void recover(){available.set(true);}
    private void forward(Socket client){
        Socket upstream=new Socket();sockets.add(client);sockets.add(upstream);
        try{upstream.connect(new InetSocketAddress(targetHost,targetPort),2000);if(!available.get()){closeSocket(client);closeSocket(upstream);return;}
            workers.submit(()->copy(client,upstream));copy(upstream,client);
        }catch(IOException ignored){closeSocket(client);closeSocket(upstream);}finally{sockets.remove(client);sockets.remove(upstream);}
    }
    private void copy(Socket from,Socket to){try{from.getInputStream().transferTo(to.getOutputStream());}catch(IOException ignored){}finally{closeSocket(from);closeSocket(to);}}
    private static void closeSocket(Socket socket){try{socket.close();}catch(IOException ignored){}}
    public void close(){closed.set(true);unavailable();try{server.close();}catch(IOException ignored){}workers.shutdownNow();}
}
