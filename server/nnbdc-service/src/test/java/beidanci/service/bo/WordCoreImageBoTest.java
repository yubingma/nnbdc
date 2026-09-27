package beidanci.service.bo;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.net.InetSocketAddress;

import javax.imageio.ImageIO;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.mockito.Mockito;

import com.sun.net.httpserver.HttpServer;

import beidanci.service.po.WordCoreImage;
import beidanci.service.util.SysParamUtil;
import okhttp3.OkHttpClient;

public class WordCoreImageBoTest {

    @TempDir
    File tempDir;

    /**
     * 单词拼写可能含文件系统与 URL 非法字符(如 "a good/great deal" 中的 "/")，
     * 文件名只能取自 wordId，否则会写到不存在的子目录，ImageIO 输出流为空并抛出晦涩的 "Output has not been set!"
     */
    @Test
    public void testDownloadAndSaveImageWithSlashInWord() throws Exception {
        byte[] png = createPng(1024, 1024);

        HttpServer server = HttpServer.create(new InetSocketAddress(0), 0);
        server.createContext("/img.png", exchange -> {
            exchange.sendResponseHeaders(200, png.length);
            exchange.getResponseBody().write(png);
            exchange.close();
        });
        server.start();

        try {
            WordCoreImageBo bo = new WordCoreImageBo();

            SysParamUtil sysParamUtil = Mockito.mock(SysParamUtil.class);
            Mockito.when(sysParamUtil.getImageBaseDir()).thenReturn(tempDir.getAbsolutePath());
            inject(bo, "sysParamUtil", sysParamUtil);
            inject(bo, "okHttpClient", new OkHttpClient());

            WordCoreImage item = new WordCoreImage();
            item.setId("e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5");
            item.setWordId("0f9e8d7c6b5a4938271605f4e3d2c1b0");
            item.setWord("a good/great deal");

            Method method = WordCoreImageBo.class.getDeclaredMethod("downloadAndSaveImage", String.class, WordCoreImage.class);
            method.setAccessible(true);
            String url = "http://127.0.0.1:" + server.getAddress().getPort() + "/img.png";

            String relativePath = (String) method.invoke(bo, url, item);

            assertEquals("core_images/core_" + item.getWordId() + ".jpeg", relativePath);

            File savedFile = new File(new File(tempDir, "core_images"), "core_" + item.getWordId() + ".jpeg");
            assertTrue(savedFile.isFile(), "意象图应成功落盘: " + savedFile.getAbsolutePath());

            BufferedImage saved = ImageIO.read(savedFile);
            assertNotNull(saved, "落盘文件必须是可解析的 JPEG");
            assertEquals(512, Math.max(saved.getWidth(), saved.getHeight()), "长边应压缩到 512");
        } finally {
            server.stop(0);
        }
    }

    private static void inject(Object target, String fieldName, Object value) throws Exception {
        Field field = WordCoreImageBo.class.getDeclaredField(fieldName);
        field.setAccessible(true);
        field.set(target, value);
    }

    private static byte[] createPng(int width, int height) throws Exception {
        BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = image.createGraphics();
        g.setColor(Color.CYAN);
        g.fillOval(0, 0, width, height);
        g.dispose();
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ImageIO.write(image, "png", out);
        return out.toByteArray();
    }
}
