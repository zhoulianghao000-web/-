package cn.pawday;
import java.io.*;
import java.net.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;

/** Real TCP fault injection: only RabbitMQ basic.ack/basic.nack frames are discarded. */
final class ConfirmDroppingProxy implements AutoCloseable {
    final ServerSocket listener;final ExecutorService workers=Executors.newVirtualThreadPerTaskExecutor();
    final List<Socket> sockets=new CopyOnWriteArrayList<>();final AtomicInteger discarded=new AtomicInteger();
    ConfirmDroppingProxy(String host,int port) throws IOException {
        listener=new ServerSocket(0,10,InetAddress.getLoopbackAddress());
        workers.submit(()->{try {while(!listener.isClosed()){
            Socket client=listener.accept(),broker=new Socket(host,port);sockets.add(client);sockets.add(broker);
            workers.submit(()->{try {client.getInputStream().transferTo(broker.getOutputStream());}catch(IOException ignored) {}});
            workers.submit(()->forwardBroker(broker,client));
        }}catch(IOException stopped) {}});
    }
    int port(){return listener.getLocalPort();}
    private void forwardBroker(Socket broker,Socket client) {
        try {var input=new DataInputStream(broker.getInputStream());var output=client.getOutputStream();
            while(!broker.isClosed()) {
                byte[] header=input.readNBytes(7);if(header.length!=7)return;
                int size=java.nio.ByteBuffer.wrap(header,3,4).getInt();if(size<0 || size>16_777_216)throw new IOException("Invalid AMQP frame");
                byte[] body=input.readNBytes(size+1);if(body.length!=size+1)return;
                boolean confirm=header[0]==1 && size>=4 && body[0]==0 && body[1]==60 && body[2]==0 && (body[3]==80 || (body[3]&255)==120);
                if(confirm){discarded.incrementAndGet();continue;}output.write(header);output.write(body);output.flush();
            }
        }catch(IOException stopped) {}
    }
    public void close() throws IOException {listener.close();for(Socket socket:sockets)socket.close();workers.shutdownNow();}
}
