package beidanci.service.util;

import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;

import javax.imageio.ImageIO;

import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

public class MyImageTest {

    @TempDir
    File tempDir;

    @Test
    public void testIsValidImageWithValidJpeg() throws IOException {
        File jpegFile = new File(tempDir, "test.jpg");
        BufferedImage img = new BufferedImage(100, 100, BufferedImage.TYPE_INT_RGB);
        Graphics2D g = img.createGraphics();
        g.setColor(Color.RED);
        g.fillRect(0, 0, 100, 100);
        g.dispose();
        ImageIO.write(img, "JPEG", jpegFile);

        Assertions.assertTrue(MyImage.isValidImage(jpegFile));
    }

    @Test
    public void testIsValidImageWithHtmlErrorPage() throws IOException {
        File htmlFile = new File(tempDir, "usual_1.jpg");
        String html = "<html><head><title>有道出错信息</title></head><body>抱歉：您所访问的资源不存在</body></html>";
        try (FileOutputStream fos = new FileOutputStream(htmlFile)) {
            fos.write(html.getBytes(StandardCharsets.UTF_8));
        }

        Assertions.assertFalse(MyImage.isValidImage(htmlFile));
    }

    @Test
    public void testIsValidImageWithCorruptedFile() throws IOException {
        File corruptFile = new File(tempDir, "corrupt.jpg");
        try (FileOutputStream fos = new FileOutputStream(corruptFile)) {
            fos.write(new byte[]{ (byte) 0xFF, (byte) 0xD8, (byte) 0xFF, 0x00, 0x00, 0x00 });
        }

        Assertions.assertFalse(MyImage.isValidImage(corruptFile));
    }

    @Test
    public void testIsValidImageWithNonExistentFile() {
        File nonExistent = new File(tempDir, "non_existent.jpg");
        Assertions.assertFalse(MyImage.isValidImage(nonExistent));
        Assertions.assertFalse(MyImage.isValidImage(null));
    }
}
