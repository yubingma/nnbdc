package beidanci.util;

import java.io.IOException;
import java.io.OutputStream;

/**
 * 计数输出流，用于统计实际传输的字节数
 */
public class CountingOutputStream extends OutputStream {
    private final OutputStream target;
    private long byteCount = 0;
    
    public CountingOutputStream(OutputStream target) {
        this.target = target;
    }
    
    @Override
    public void write(int b) throws IOException {
        target.write(b);
        byteCount++;
    }
    
    @Override
    public void write(byte[] b) throws IOException {
        target.write(b);
        byteCount += b.length;
    }
    
    @Override
    public void write(byte[] b, int off, int len) throws IOException {
        target.write(b, off, len);
        byteCount += len;
    }
    
    @Override
    public void flush() throws IOException {
        target.flush();
    }
    
    @Override
    public void close() throws IOException {
        target.close();
    }
    
    public long getByteCount() {
        return byteCount;
    }
} 