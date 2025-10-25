package beidanci.service.util;

import java.awt.Color;
import java.awt.image.BufferedImage;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.util.Iterator;

import javax.imageio.ImageIO;
import javax.imageio.ImageReader;
import javax.imageio.stream.ImageInputStream;

import org.apache.commons.io.FileUtils;

import com.mortennobel.imagescaling.ResampleOp;

/**
 * 图片缩放工具类
 *
 * @author sunnymoon
 */
public class MyImage {
    /**
     * 接收File输出图片
     *
     * @param targetWidth
     * @param targetHeight
     * @param format
     * @return
     * @throws IOException
     */
    public static void resizeImage(File srcFile, File targetFile, Integer targetWidth, Integer targetHeight,
                                   String format, boolean keepRatio) throws IOException {
        BufferedImage inputBufImage = ImageIO.read(srcFile);
        // 某些格式（如 WebP）默认 ImageIO 无法解析，直接按原文件复制，避免 NPE
        if (inputBufImage == null) {
            FileUtils.copyFile(srcFile, targetFile);
            return;
        }

        // 如果原图片尺寸和格式都与目标相同，则不需要转换
        String srcFormat = getImageFormat(srcFile);
        if (inputBufImage.getWidth() == targetWidth && inputBufImage.getHeight() == targetHeight
                && srcFormat != null && srcFormat.equalsIgnoreCase(format)) {
            FileUtils.copyFile(srcFile, targetFile);
            return;
        }

        // create a blank, RGB, same width and height, and a white background
        BufferedImage newBufferedImage = new BufferedImage(inputBufImage.getWidth(), inputBufImage.getHeight(),
                BufferedImage.TYPE_INT_RGB);
        newBufferedImage.createGraphics().drawImage(inputBufImage, 0, 0, Color.WHITE, null);

        // 保持原图的长宽比
        if (keepRatio) {
            double factor = Math.min((targetWidth + 0.0) / inputBufImage.getWidth(), (targetHeight + 0.0) / inputBufImage.getHeight());
            targetWidth = (int) Math.round(inputBufImage.getWidth() * factor);
            targetHeight = (int) Math.round(inputBufImage.getHeight() * factor);
        }

        ResampleOp resampleOp = new ResampleOp(targetWidth, targetHeight);// 转换
        BufferedImage rescaledTomato = resampleOp.filter(newBufferedImage, null);
        if (canWriteFormat(format)) {
            ImageIO.write(rescaledTomato, format, targetFile);
        } else {
            // 当前 JRE 不支持该格式写出，直接复制原图
            FileUtils.copyFile(srcFile, targetFile);
        }
    }

    public static byte[] readBytesFromIS(InputStream is) throws IOException {
        int total = is.available();
        byte[] bs = new byte[total];
        is.read(bs);
        return bs;
    }

    public static String getImageFormat(File imageFile) throws IOException {
        try (ImageInputStream iis = ImageIO.createImageInputStream(imageFile)) {
            for (Iterator<ImageReader> i = ImageIO.getImageReaders(iis); i.hasNext(); ) {
                ImageReader reader = i.next();
                return reader.getFormatName();
            }
            return null;
        }
    }

    public static boolean canWriteFormat(String format) {
        if (format == null) return false;
        return ImageIO.getImageWritersByFormatName(format).hasNext();
    }

    public static String detectFormat(byte[] data) {
        if (data == null || data.length < 12) return null;
        // JPEG
        if ((data[0] & 0xFF) == 0xFF && (data[1] & 0xFF) == 0xD8 && (data[2] & 0xFF) == 0xFF) return "JPEG";
        // PNG
        if ((data[0] & 0xFF) == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47 && data[4] == 0x0D && data[5] == 0x0A && data[6] == 0x1A && data[7] == 0x0A) return "PNG";
        // GIF
        if (data[0] == 'G' && data[1] == 'I' && data[2] == 'F' && data[3] == '8' && (data[4] == '7' || data[4] == '9') && data[5] == 'a') return "GIF";
        // WEBP: RIFF....WEBP
        if (data[0] == 'R' && data[1] == 'I' && data[2] == 'F' && data[3] == 'F' && data[8] == 'W' && data[9] == 'E' && data[10] == 'B' && data[11] == 'P') return "WEBP";
        // BMP
        if (data[0] == 'B' && data[1] == 'M') return "BMP";
        return null;
    }

    public static String detectFormat(File imageFile) throws IOException {
        byte[] header = Files.readAllBytes(imageFile.toPath());
        // 仅读取前几个字节也足够，但这里简化处理
        return detectFormat(header);
    }

    public static String normalizeExtByFormat(String format) {
        if (format == null) return "jpg";
        return switch (format.toUpperCase()) {
            case "JPEG" -> "jpg";
            case "PNG" -> "png";
            case "GIF" -> "gif";
            case "BMP" -> "bmp";
            case "WEBP" -> "webp";
            default -> "jpg";
        };
    }

    // 测试：只测试了字节流的方式，其它的相对简单，没有一一测试
    public static void main(String[] args) throws IOException {
        int width = 470;
        int height = 470;
        File inputFile = new File("F:\\p681.jpg");
        System.out.printf("src format name: %s%n", getImageFormat(inputFile));
        MyImage.resizeImage(inputFile, new File("F:\\to.jpg"), width, height, "JPEG", true);
    }
}
