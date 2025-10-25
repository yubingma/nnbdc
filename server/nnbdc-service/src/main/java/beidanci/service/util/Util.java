package beidanci.service.util;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.io.RandomAccessFile;
import java.io.StringWriter;
import java.io.UnsupportedEncodingException;
import java.net.HttpURLConnection;
import java.net.SocketTimeoutException;
import java.net.URL;
import java.net.URLConnection;
import java.net.URLEncoder;
import java.security.GeneralSecurityException;
import java.security.NoSuchAlgorithmException;
import java.security.cert.X509Certificate;
import java.sql.Timestamp;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.Set;
import java.util.StringTokenizer;
import java.util.UUID;
import java.util.stream.Collectors;

import javax.net.ssl.HostnameVerifier;
import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLSession;
import javax.net.ssl.X509TrustManager;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

import org.apache.commons.httpclient.HttpClient;
import org.apache.commons.httpclient.HttpMethod;
import org.apache.commons.httpclient.methods.GetMethod;
import org.apache.commons.io.FileUtils;
import org.apache.commons.lang.StringUtils;
import org.apache.commons.mail.EmailException;
import org.apache.commons.mail.SimpleEmail;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.BeanUtils;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import com.fasterxml.jackson.annotation.JsonInclude.Include;
import com.fasterxml.jackson.core.JsonFactory;
import com.fasterxml.jackson.core.JsonGenerator;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.jcraft.jsch.ChannelSftp;

import beidanci.api.Result;
import beidanci.api.model.DictVo;
import beidanci.api.model.DictWordVo;
import beidanci.api.model.MeaningItemVo;
import beidanci.api.model.PagedResults;
import beidanci.api.model.SentenceVo;
import beidanci.api.model.SynonymVo;
import beidanci.api.model.UserVo;
import beidanci.api.model.WordShortDescChineseVo;
import beidanci.api.model.WordVo;
import beidanci.service.SessionData;
import beidanci.service.bo.DictBo;
import beidanci.service.bo.LearningDictBo;
import beidanci.service.bo.SysParamBo;
import beidanci.service.bo.UserBo;
import beidanci.service.po.Dict;
import beidanci.service.po.DictWord;
import beidanci.service.po.LearningDict;
import beidanci.service.po.LearningDictId;
import beidanci.service.po.Level;
import beidanci.service.po.SysParam;
import beidanci.service.po.User;
import beidanci.service.po.Word;
import beidanci.service.po.WordShortDescChinese;
import beidanci.service.store.WordCache;
import beidanci.util.Constants;
import beidanci.util.MD5Utils;
import beidanci.util.Utils;
import static beidanci.util.Utils.getPureDate;
import net.sf.json.JSONObject;
import net.sf.json.JSONSerializer;

public class Util {
    private static final Logger log = LoggerFactory.getLogger(Util.class);

    public static boolean isInTransaction() {
        return TransactionSynchronizationManager.isActualTransactionActive();
    }

    public static String makeJson(Object data) throws IOException {
        ObjectMapper mapper = new ObjectMapper();
        mapper.setSerializationInclusion(Include.NON_NULL);
        // mapper.setDateFormat(new SimpleDateFormat("yyyy-MM-dd HH:mm:ss"));
        mapper.configure(SerializationFeature.WRITE_ENUMS_USING_TO_STRING, true);
        mapper.configure(SerializationFeature.FAIL_ON_EMPTY_BEANS, false);
        StringWriter sw = new StringWriter();
        try (@SuppressWarnings("deprecation")
        JsonGenerator gen = new JsonFactory().createJsonGenerator(sw)) {
            mapper.writeValue(gen, data);
        }
        String json = sw.toString();
        // System.out.println(json);
        return json;
    }

    public static void appendToFile(String content, File file, String encoding) throws IOException {
        try (BufferedWriter writer = new BufferedWriter(
                new OutputStreamWriter(new FileOutputStream(file, true), encoding))) {
            writer.write(content);
        }
    }

    public static String deleteLastChar(String str) {
        return str.substring(0, str.length() - 1);
    }

    private static final myX509TrustManager xtm;

    private static final myHostnameVerifier hnv;

    static {
        xtm = new myX509TrustManager();
        hnv = new myHostnameVerifier();

        SSLContext sslContext = null;
        try {
            sslContext = SSLContext.getInstance("SSLv3"); // 或SSL/TLS
            X509TrustManager[] xtmArray = new X509TrustManager[] { xtm };
            sslContext.init(null, xtmArray, new java.security.SecureRandom());
        } catch (GeneralSecurityException e) {
            log.error("SSLContext initialization failed", e);
        }
        if (sslContext != null) {
            HttpsURLConnection.setDefaultSSLSocketFactory(sslContext.getSocketFactory());
        }
        HttpsURLConnection.setDefaultHostnameVerifier(hnv);
    }

    private static class myX509TrustManager implements X509TrustManager {

        @Override
        public void checkClientTrusted(X509Certificate[] chain, String authType) {
        }

        @Override
        public void checkServerTrusted(X509Certificate[] chain, String authType) {
        }

        @Override
        public X509Certificate[] getAcceptedIssuers() {
            return null;
        }
    }

    private static class myHostnameVerifier implements HostnameVerifier {

        @Override
        public boolean verify(String hostname, SSLSession session) {
            return true;
        }
    }

    public static String getHtml(String urlString, String srcCharSet, String dstCharSet, boolean printResponse)
            throws UnsupportedEncodingException, IOException {
        log.info("Getting page:" + urlString);

        StringBuilder html = new StringBuilder();
        URL url = new URL(urlString);
        HttpURLConnection conn = (HttpURLConnection) url.openConnection();

        conn.setRequestProperty("User-Agent",
                "compatible; MSIE 8.0; Windows NT 5.1; Trident/4.0; .NET CLR 1.1.4322; .NET CLR 2.0.50727; .NET CLR 3.0.4506.2152; .NET CLR 3.5.30729; .NET4.0C; .NET4.0E");
        try (InputStreamReader isr = new InputStreamReader(conn.getInputStream(), srcCharSet);
                BufferedReader br = new BufferedReader(isr)) {
            String temp;
            while ((temp = br.readLine()) != null) {
                html.append(temp).append("\n");
            }
        }

        String response = new String(html.toString().getBytes(dstCharSet));
        if (printResponse) {
            log.info("response: " + response);
        }
        return response;
    }

    /**
     * 从一段混杂了xml标记的文本中取出所有的xml标记
     *
     * @param content
     * @return
     */
    public static String deleteAllXmlTag(String content) {

        return content.replaceAll("<{1}[^<>]*>{1}", "");

    }

    /**
     * 不用正则表达式的字符串替换
     *
     * @param aInput
     * @param aOldPattern
     * @param aNewPattern
     * @return
     */
    public static String replaceOld(final String aInput, final String aOldPattern, final String aNewPattern) {
        if (aOldPattern.equals("")) {
            throw new IllegalArgumentException("Old pattern must have content.");
        }
        final StringBuffer result = new StringBuffer();
        // startIdx and idxOld delimit various chunks of aInput; these
        // chunks always end where aOldPattern begins
        int startIdx = 0;
        int idxOld;
        while ((idxOld = aInput.indexOf(aOldPattern, startIdx)) >= 0) {
            // grab a part of aInput which does not include aOldPattern
            result.append(aInput.substring(startIdx, idxOld));
            // add aNewPattern to take place of aOldPattern
            result.append(aNewPattern);
            // reset the startIdx to just after the current match, to see
            // if there are any further matches
            startIdx = idxOld + aOldPattern.length();
        }
        // the final chunk will go to the end of aInput
        result.append(aInput.substring(startIdx));
        return result.toString();
    }

    public static boolean isEnglishChar(char c) {
        return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
    }

    public static boolean isNumber(String str) {
        if (str.length() == 0) {
            return false;
        }
        for (int i = 0; i < str.length(); i++) {
            char cTemp = str.charAt(i);
            if (cTemp < '0' || cTemp > '9')
                return false;
        }
        return true;
    }

    public static boolean isStringEnglishWord(String str) {
        for (int i = 0; i < str.length(); i++) {
            char c = str.charAt(i);
            if (!(c >= 'A' && c <= 'Z') && !(c >= 'a' && c <= 'z') && (c != ' ') && (c != '-')) {
                return false;
            }
        }
        return true;
    }

    public static String loadStringFromFile(File file, String encoding) throws IOException {
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(new FileInputStream(file), encoding))) {
            StringBuilder builder = new StringBuilder();
            char[] chars = new char[4096];
            int length = 0;

            while (0 < (length = reader.read(chars))) {

                builder.append(chars, 0, length);

            }
            return builder.toString();
        }
    }

    public static void println(String msg) {
        System.out.println(msg);
    }

    public static String replaceDoubleSpace(String str) {
        while (str.contains("  ")) {
            str = str.replaceAll("  ", " ");
        }
        return str;
    }

    public static void saveToFile(String content, File file, String encoding) throws IOException {

        try (BufferedWriter writer = new BufferedWriter(new OutputStreamWriter(new FileOutputStream(file, false), encoding))) {
            writer.write(content);
        }
    }

    public static SessionData getSessionData(HttpServletRequest request) {
        SessionData sessionData = (SessionData) request.getSession().getAttribute(SessionData.SESSION_DATA);
        return sessionData;
    }

    @SuppressWarnings("deprecation")
    public static boolean isSameDay(Date date1, Date date2) {
        if (date1 == null || date2 == null) {
            return false;
        } else {
            return (date1.getMonth() == date2.getMonth() && date1.getYear() == date2.getYear()
                    && date1.getDate() == date2.getDate());
        }
    }

    public static void downloadFile(URL url, File saveToFile) throws IOException {
        // 下载网络文件
        int byteread;

        URLConnection conn = url.openConnection();
        conn.setReadTimeout(5000);

        InputStream inStream = conn.getInputStream();
        File tempFile = new File(saveToFile.getAbsoluteFile() + ".temp");
        if (tempFile.exists()) {
            if (!tempFile.delete()) {
                throw new RuntimeException(String.format("删除临时文件[%s]失败!", tempFile.getAbsoluteFile()));
            }
        }

        FileOutputStream fs = new FileOutputStream(tempFile);
        byte[] buffer = new byte[1024 * 8];

        try {
            while ((byteread = inStream.read(buffer)) != -1) {
                fs.write(buffer, 0, byteread);
            }

            // 下载完成
            fs.close();
            FileUtils.copyFile(tempFile, saveToFile);
            tempFile.delete();
        } catch (SocketTimeoutException e) {
            log.warn("Read 超时, 再次尝试下载");
            fs.close();
            tempFile.delete();
        }

    }

    /**
     * 为指定的文件创建临时文件
     *
     * @param forFile
     * @return
     */
    public static File createTempFile(File forFile) {
        File tempFile = new File(forFile.getPath() + "_temp");
        if (tempFile.exists()) {
            if (!tempFile.delete()) {
                throw new RuntimeException("File can not be deleted: " + tempFile.getPath());
            }
        }
        return tempFile;
    }

    /**
     * 把临时文件重命名为指定文件F
     *
     * @param tempFile
     */
    public static void renameTempFile(File tempFile, File toFile) {
        System.gc();
        if (!toFile.delete()) {
            throw new RuntimeException("File can not be deleted: " + toFile.getPath());
        }
        if (!tempFile.renameTo(toFile)) {
            throw new RuntimeException(
                    String.format("File[%s] can not be renamed to [%s]", tempFile.getPath(), toFile.getPath()));
        }
    }


    /**
     * 判断一个字符串是一个合法的单词（或句子）
     *
     * @param str
     */
    public static boolean isValidWord(String str) {
        return str.matches("[a-zA-Z0-9?'!;=\\s\\-\\,\\.\\(\\)]*");
    }

    public static boolean isValidUserName(String userName) {
        return userName.matches("^[A-Za-z0-9_-]+$");
    }

    public static boolean isReservedUserName(String userName) {
        return userName.toLowerCase().startsWith("guest") || userName.equalsIgnoreCase("all")
                || userName.equalsIgnoreCase(Constants.SYS_USER_SYS);
    }

    /**
     * 对指定文件的每一行进行规格化，如消除多余空格
     *
     * @throws IOException
     */
    public static void uniformFile(File file) throws IOException {
        // 创建临时文件，用于保存新版本的单词书
        File tempFile = Util.createTempFile(file);
        try (RandomAccessFile raf = new RandomAccessFile(tempFile, "rw")) {
            raf.seek(0);

            // 经原单词书的每一行复制到临时单词书，在此过程中进行规格化
            try (
                    BufferedReader reader = new BufferedReader(new InputStreamReader(new FileInputStream(file), "UTF-8"))) {
                String wordStr = reader.readLine();
                while (wordStr != null) {
                    String uniformedStr = Utils.uniformString(wordStr);
                    if (!uniformedStr.equalsIgnoreCase("")) {
                        raf.write(Utils.uniformString(wordStr).getBytes("UTF-8"));
                        raf.write("\n".getBytes("UTF-8"));
                    }
                    wordStr = reader.readLine();
                }
            }
        }

        // 文件改名，替换原始文件
        Util.renameTempFile(tempFile, file);
    }

    /**
     * MD5的算法在RFC1321 中定义<br/>
     * 在RFC 1321中，给出了Test suite用来检验你的实现是否正确：<br/>
     * MD5 ("") = d41d8cd98f00b204e9800998ecf8427e<br/>
     * MD5 ("a") = 0cc175b9c0f1b6a831c399e269772661<br/>
     * MD5 ("abc") = 900150983cd24fb0d6963f7d28e17f72<br/>
     * MD5 ("message digest") = f96b697d7cb7938d525a2f31aaf161d0<br/>
     * MD5 ("abcdefghijklmnopqrstuvwxyz") = c3fcd3d76192e4007dfb496cca67e13b<br/>
     * <br/>
     *
     * @author haogj<br />
     *         <br/>
     *         传入参数：一个字节数组<br/>
     *         传出参数：字节数组的 MD5 结果字符串<br/>
     */
    public static String getMD5(byte[] source) {
        String s = null;
        char hexDigits[] = { // 用来将字节转换成 16 进制表示的字符
                '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f' };
        try {
            java.security.MessageDigest md = java.security.MessageDigest.getInstance("MD5");
            md.update(source);
            byte tmp[] = md.digest(); // MD5 的计算结果是一个 128 位的长整数，
            // 用字节表示就是 16 个字节
            char str[] = new char[16 * 2]; // 每个字节用 16 进制表示的话，使用两个字符，
            // 所以表示成 16 进制需要 32 个字符
            int k = 0; // 表示转换结果中对应的字符位置
            for (int i = 0; i < 16; i++) { // 从第一个字节开始，对 MD5 的每一个字节
                // 转换成 16 进制字符的转换
                byte byte0 = tmp[i]; // 取第 i 个字节
                str[k++] = hexDigits[byte0 >>> 4 & 0xf]; // 取字节中高 4 位的数字转换,
                // >>>
                // 为逻辑右移，将符号位一起右移
                str[k++] = hexDigits[byte0 & 0xf]; // 取字节中低 4 位的数字转换
            }
            s = new String(str); // 换后的结果转换为字符串

        } catch (NoSuchAlgorithmException e) {
            log.error("getMD5 failed", e);
            throw new RuntimeException(e);
        }
        return s;
    }

    public static void sendEmailToNnbdcCustomerSerivce(String subject, String content) {
        sendSimpleEmail("mmyybb3000@hotmail.com", "myb", subject,
                content);
    }

    @SuppressWarnings("deprecation")
    public static void sendSimpleEmail(String toEmail, String toName, String subject, String content) {
        new Thread(() -> {
            try {
                log.info(String.format("向%s发送邮件，主题：%s", toEmail, subject)); 
                SimpleEmail email = new SimpleEmail();
                email.setHostName("smtp.office365.com");
                email.setSmtpPort(587);
                email.setAuthentication("mmyybb3000@hotmail.com", System.getenv("nnbdc_server_pwd"));
                email.setTLS(true);
                email.setDebug(true);
                email.setCharset("UTF-8");
                email.addTo(toEmail, toName);
                email.setFrom("mmyybb3000@hotmail.com", "牛牛背单词");
                email.setSubject(subject);
                email.setMsg(content);
                email.send();
            } catch (EmailException e) {
                log.error("", e);
            }
        }).start();

    }

    public static boolean isUserAgentMobile(HttpServletRequest request) {
        String userAgent = request.getHeader("User-Agent");
        if (userAgent == null) {
            return false;
        }

        String[] mobileKeyWords = { "Android", "iPhone", "iPod", "iPad", "Windows Phone", "MQQBrowser" };

        if (userAgent.contains("Windows NT") && !userAgent.contains("compatible; MSIE 9.0;")) {
            return false;
        }

        if (userAgent.contains("Macintosh")) {
            return false;
        }

        for (String mobileKeyWord : mobileKeyWords) {
            if (userAgent.contains(mobileKeyWord)) {
                return true;
            }
        }

        return false;
    }

    public static String getNickNameOfUser(User user) {
        if (user == null) {
            return "";
        }
        String nickName = user.getUserName();

        if (!isStringEmpty(user.getNickName())) {
            nickName = user.getNickName();
        }

        return nickName;
    }

    public static String getNickNameOfUser(UserVo user) {
        if (user == null) {
            return "";
        }
        String nickName = user.getUserName();

        if (!isStringEmpty(user.getNickName())) {
            nickName = user.getNickName();
        }

        return nickName;
    }

    public static boolean isStringEmpty(String str) {
        return str == null || str.trim().length() == 0;
    }

    public static String array2Str(String[] array) {
        StringBuilder sb = new StringBuilder();
        sb.append("[");
        for (int i = 0; i < array.length; i++) {
            sb.append(array[i]);
            if (i < array.length - 1) {
                sb.append(",");
            }
        }
        sb.append("]");
        return sb.toString();
    }

    public static <T> String sendBooleanResponse(boolean boolValue, String msg, T data, HttpServletResponse response)
            throws IOException {
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        try (PrintWriter out = response.getWriter()) {
            Result<T> ajaxResult = new Result<>(boolValue ? "0000" : "0001", msg, data);

            String json = makeJson(ajaxResult);

            out.println(json);
            return json;
        }
    }

    public static void sendAjaxResult(Result<? extends Object> result, HttpServletResponse response)
            throws IOException {
        response.setContentType("application/json");
        try (PrintWriter out = response.getWriter()) {
            out.println((JSONSerializer.toJSON(result)).toString());
        }
    }

    public static String getUserAgent(HttpServletRequest request) {
        return request.getHeader("User-Agent");
    }

    public static User genNewUser(String userName, String password, String nickName, String email, User invitedBy,
            SysParamBo sysParamBo, DictBo dictBo, UserBo userBo, LearningDictBo learningDictBo, boolean isSysUser) {
        User user = new User();
        user.setUserName(userName.toLowerCase());
        user.setPassword(password);
        user.setNickName(EmojiFilter.filterEmoji(nickName));
        user.setEmail(email);
        SysParam sysParam = sysParamBo.findById("DefaultWordsPerDay", false);
        user.setWordsPerDay(Integer.valueOf(sysParam.getParamValue()));
        user.setCreateTime(new Timestamp(new Date().getTime()));
        user.setLearnedDays(0);
        user.setLearningFinished(false);
        user.setLastLearningPosition(-1);
        user.setLastLearningMode(-1);
        user.setMasteredWordsCount(0);
        user.setCowDung(20); // 注册送泡泡糖
        user.setThrowDiceChance(0);
        user.setInvitedBy(invitedBy);
        user.setInviteAwardTaken(false);
        user.setIsSuper(false);
        user.setIsAdmin(false);
        user.setDakaDayCount(0);
        user.setAutoPlaySentence(false);
        user.setAutoPlayWord(true);
        user.setShowAnswersDirectly(true);
        user.setContinuousDakaDayCount(0);
        user.setMaxContinuousDakaDayCount(0);
        user.setDakaScore(0);
        user.setGameScore(0);
        Level level = new Level();
        level.setId("1"); // 白丁
        user.setLevel(level);
        user.setIsInputor(false);
        user.setEnableAllWrong(false);
        user.setAsrPassRule("ONE");
        user.setIsSysUser(isSysUser);
        userBo.createEntity(user);
        log.info(String.format("创建了新用户:[%s]", user.getDisplayNickName()));

        // 创建用户的生词本
        Dict rawDict = new Dict();
        rawDict.setName("生词本");
        rawDict.setWordCount(0);
        rawDict.setIsReady(true);
        rawDict.setIsShared(false);
        rawDict.setVisible(true);
        rawDict.setOwner(user);
        dictBo.createEntity(rawDict);

        LearningDictId id = new LearningDictId(user.getId(), rawDict.getId());
        LearningDict learningDict = new LearningDict(id, rawDict, user, false, true);
        learningDictBo.createEntity(learningDict);

        return user;
    }

    public static Map<String, String> parseUrlParams(String paramStr) {
        Map<String, String> params = new HashMap<>();
        String[] parts = paramStr.split("&");
        for (String param : parts) {
            if (param.length() > 0) {
                String[] nameAndValue = param.split("=");
                params.put(nameAndValue[0], nameAndValue[1]);
            }
        }
        return params;
    }

    @SuppressWarnings("unchecked")
    public static Map<String, Object> parseJsonToMap(String response) {
        JSONObject jsonObject = JSONObject.fromObject(response);
        Map<String, Object> map = jsonObject;
        return map;

    }

    /**
     * 从ip的字符串形式得到字节数组形式
     *
     * @param ip 字符串形式的ip
     * @return 字节数组形式的ip
     */
    public static byte[] getIpByteArrayFromString(String ip) {
        byte[] ret = new byte[4];
        StringTokenizer st = new StringTokenizer(ip, ".");

        try {
            ret[0] = (byte) (Integer.parseInt(st.nextToken()) & 0xFF);
            ret[1] = (byte) (Integer.parseInt(st.nextToken()) & 0xFF);
            ret[2] = (byte) (Integer.parseInt(st.nextToken()) & 0xFF);
            ret[3] = (byte) (Integer.parseInt(st.nextToken()) & 0xFF);
        } catch (NumberFormatException e) {
            log.error("无法解析的地址：" + ip);
        }

        return ret;
    }

    /**
     * @param ip ip的字节数组形式
     * @return 字符串形式的ip
     */
    public static String getIpStringFromBytes(byte[] ip) {
        StringBuilder sb = new StringBuilder();
        sb.delete(0, sb.length());
        sb.append(ip[0] & 0xFF);
        sb.append('.');
        sb.append(ip[1] & 0xFF);
        sb.append('.');
        sb.append(ip[2] & 0xFF);
        sb.append('.');
        sb.append(ip[3] & 0xFF);
        return sb.toString();
    }

    /**
     * 根据某种编码方式将字节数组转换成字符串
     *
     * @param b        字节数组
     * @param offset   要转换的起始位置
     * @param len      要转换的长度
     * @param encoding 编码方式
     * @return 如果encoding不支持，返回一个缺省编码的字符串
     */
    public static String getString(byte[] b, int offset, int len, String encoding) {
        try {
            return new String(b, offset, len, encoding);
        } catch (UnsupportedEncodingException e) {
            return new String(b, offset, len);
        }
    }

    public static void uploadFile(String srcFile, String destFile) throws Exception {
        Map<String, String> sftpDetails = new HashMap<>();
        // 设置主机ip，端口，用户名，密码
        sftpDetails.put(SFTPConstants.SFTP_REQ_HOST, "116.255.247.39");
        sftpDetails.put(SFTPConstants.SFTP_REQ_USERNAME, "root");
        sftpDetails.put(SFTPConstants.SFTP_REQ_PASSWORD, "y4v6y5");
        sftpDetails.put(SFTPConstants.SFTP_REQ_PORT, "22000");

        SFTPChannel channel = new SFTPChannel();
        ChannelSftp chSftp = channel.getChannel(sftpDetails, 60000);

        chSftp.put(srcFile, destFile, ChannelSftp.OVERWRITE);

        chSftp.quit();
        channel.closeChannel();
    }

    /**
     * 从google下载英文句子的发音文件, 并保存在指定文件中，如果文件不存在则自动创建
     *
     * @param sentence
     * @throws IOException
     */
    @SuppressWarnings("deprecation")
    public static void getSoundOfSentence(String sentence, File destFile) throws IOException {

        if (sentence.length() > 100) {
            return;
        }

        HttpClient httpClient = new HttpClient();
        String url = String.format("http://translate.google.cn/translate_tts?tl=en&q=%s", URLEncoder.encode(sentence));
        HttpMethod method = new GetMethod(url);
        log.info(String.format("从google下载TTS数据, url:%s", url));
        httpClient.executeMethod(method);

        if (method.getStatusCode() == 200) {
            int bytesum = 0;
            int byteread;
            byte[] buffer = new byte[1204];
            InputStream is = method.getResponseBodyAsStream();
            try (FileOutputStream fs = new FileOutputStream(destFile)) {
                while ((byteread = is.read(buffer)) != -1) {
                    bytesum += byteread;
                    fs.write(buffer, 0, byteread);
                }
            }
            log.info(String.format("从google下载TTS数据[%d]bytes", bytesum));
        } else {
            log.info(String.format("从google下载TTS数据失败：%s, 句子长度[%s]", method.getStatusLine(), sentence.length()));
        }

        method.releaseConnection();
    }

    /**
     * 计算句子的摘要信息，以便区分句子
     *
     * @param sentence
     * @return
     */
    public static String makeSentenceDigest(String sentence) {
        return MD5Utils.md5(sentence);
    }

    /**
     * 转换用户提交的内容，因为其中可能含有攻击脚本。
     *
     * @param content
     * @return
     */
    public static String purifyContent(String content) {
        return content.replaceAll("'", "’").replaceAll("\"", "”").replaceAll("&", "§").replace("script", "ｓｃｒｉｐｔ");
    }



    /**
     * 根据是否含有x-requested-with头来确定请求是否是AJAX请求。<br>
     * 由于/checkUser.do可能是跨域请求，而浏览器对跨域请求有特殊限制，无法为请求附加x-requested-with头，所以/checkUser.
     * do直接认为是AJAX请求
     *
     * @param request
     * @return
     */
    public static boolean isAjaxRequest(HttpServletRequest request) {
        String requestedWith = request.getHeader("x-requested-with");
        return "XMLHttpRequest".equalsIgnoreCase(requestedWith) || request.getRequestURI().contains("/checkUser.do");
    }

    /**
     * 获取一个单词的所有可能变体（如-ing, -ed）
     *
     * @return
     */
    public static List<String> getVariantsOfWord(String word) {
        List<String> variants = new ArrayList<>();

        // 自身
        variants.add(word);

        // -s -es
        if (word.endsWith("s") || word.endsWith("ch")) {
            variants.add(word + "es");
        } else if (!word.equalsIgnoreCase("hi")) {
            variants.add(word + "s");
        }

        // -ing -ed
        if (word.endsWith("e")) {
            variants.add(word.substring(0, word.length() - 1) + "ing");
            variants.add(word + "d");
        } else {
            variants.add(word + "ed");
        }

        return variants;
    }

    public static boolean getEyeMode(HttpServletRequest request) {
        Boolean eyeMode = (Boolean) request.getSession().getAttribute("eyeMode");
        eyeMode = eyeMode == null ? false : eyeMode;
        return eyeMode;
    }

    public static boolean isAllDictsFinished(List<LearningDict> learningDicts) {
        boolean allDictsFinished = true;
        for (LearningDict dict : learningDicts) {
            Integer currentWordSeq = dict.getCurrentWordSeq();
            Integer wordCount = dict.getDict().getWordCount();
            boolean isLearningFinished = (currentWordSeq == null ? -1 : currentWordSeq) >=
                    (wordCount == null ? 0 : wordCount);
            if (!isLearningFinished) {
                allDictsFinished = false;
                break;
            }
        }
        return allDictsFinished;
    }

    /**
     * 生成指定范围内的随机整数
     *
     * @param min
     * @param max
     * @return
     */
    public static int genRandomNumber(int min, int max) {
        Random random = new Random();
        return random.nextInt(max) % (max - min + 1) + min;
    }

    /**
     * 获取客户端IP
     *
     * @param request
     * @return
     */
    public static String getClientIP(HttpServletRequest request) {
        String remoteAddr = request.getHeader("X-Forwarded-For"); // X-Forwarded-For是nginx配置文件中定义的，保存了客户端实际IP地址
        if (remoteAddr == null) {
            remoteAddr = request.getRemoteAddr();
        } else {
            remoteAddr = remoteAddr.split(",")[0]; // 在有多个nginx的情况下，X-Forwarded-For的值是客户端到服务端路径中每个主机的IP地址（以逗号分隔），其中第一个是客户端的IP地址
        }
        return remoteAddr;
    }

    public static Date removeTimePart(Date date) throws java.text.ParseException {
        SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd");
        String s = sdf.format(date);
        return sdf.parse(s);
    }

    /**
     * List去重
     *
     * @param list
     */
    public static <T> void removeDuplicate(List<T> list) {
        LinkedHashSet<T> set = new LinkedHashSet<>(list.size());
        set.addAll(list);
        list.clear();
        list.addAll(set);
    }

    public static boolean isEnglish(String str) throws UnsupportedEncodingException {
        byte[] bytes = str.getBytes("utf-8");
        int i = bytes.length;// i为字节长度
        int j = str.length();// j为字符长度
        boolean result = i == j;
        return result;
    }

    /**
     * 把字符串中的中文符号转为英文
     *
     * @param str
     * @return
     */
    public static String replaceChineseSymbol(String str) {
        return str.replaceAll("，", ",")
                .replaceAll("：", ":")
                .replaceAll("。", ".")
                .replaceAll("？", "?")
                .replaceAll("“", "\"")
                .replaceAll("”", "\"")
                .replaceAll("‘", "'")
                .replaceAll("’", "'")
                .replaceAll("！", "!");
    }

    public static List<String> splitSentence2Words(String english) {
        String[] words = english.split(" |\\.|,|!|\"|\\?|\\(|\\)|:|;");
        List<String> puredWords = new ArrayList<>(words.length);
        for (String spell : words) {
            spell = StringUtils.strip(spell, " '-");
            if (!StringUtils.isEmpty(spell)) {
                puredWords.add(spell);
            }
        }
        return puredWords;
    }

    /**
     * 根据用户选择的单词书对word vo进行收缩
     *
     * @param srcWordVo
     * @param user
     * @return
     */
    public static WordVo shrinkWordVo(final WordVo srcWordVo, User user, final int maxSentenceCount,
            LearningDictBo learningDictBo, boolean removeSimilarWords) {
        List<LearningDict> learningDicts = learningDictBo.getLearningDictsOfUser(user);
        List<Dict> selectedDicts = new ArrayList<>(learningDicts.size());
        for (LearningDict selectedDict : learningDicts) {
            selectedDicts.add(selectedDict.getDict());
        }
        return shrinkWordVo(srcWordVo, selectedDicts, maxSentenceCount, removeSimilarWords);
    }

    private static List<MeaningItemVo> shrinkMeanItems(List<MeaningItemVo> srcMeaningItems) {
        List<MeaningItemVo> meaningItemVos = new ArrayList<>(srcMeaningItems.size());
        for (MeaningItemVo meaningItemVo : srcMeaningItems) {
            MeaningItemVo destMeaningItemVo = new MeaningItemVo();
            meaningItemVos.add(destMeaningItemVo);
            BeanUtils.copyProperties(meaningItemVo, destMeaningItemVo, "dict", "createTime", "updateTime");
            if (meaningItemVo.getDict() != null) {
                DictVo destDict = new DictVo();
                BeanUtils.copyProperties(meaningItemVo.getDict(), destDict, "owner");
                destMeaningItemVo.setDict(destDict);
            }
        }
        return meaningItemVos;
    }

    /**
     * 根据指定的单词书，对WordVo进行收缩（去除指定单词书范围之外的释义项）
     *
     * @param wordVo
     * @param selectedDictVos
     * @return
     */
    public static WordVo shrinkWordVo(WordVo srcWordVo, Set<String> dictIds, final int maxSentenceCount,
            boolean removeSimilarWords) {
        WordVo destWordVo = new WordVo();
        BeanUtils.copyProperties(srcWordVo, destWordVo, "meaningItems", "similarWords");

        // 复制meaningItems
        destWordVo.setMeaningItems(shrinkMeanItems(srcWordVo.getMeaningItems()));

        // 复制similarWords
        if (srcWordVo.getSimilarWords() != null && !removeSimilarWords) {
            List<WordVo> similarWords = new ArrayList<>(srcWordVo.getSimilarWords().size());
            destWordVo.setSimilarWords(similarWords);
            for (WordVo wordVo : srcWordVo.getSimilarWords()) {
                WordVo similarWord = new WordVo();
                similarWords.add(similarWord);
                BeanUtils.copyProperties(wordVo, similarWord, "meaningItems");
                similarWord.setMeaningItems(shrinkMeanItems(wordVo.getMeaningItems()));
            }
        }

        // 去除单词不属于指定单词书的释义
        List<MeaningItemVo> meaningItemVos = new ArrayList<>();
        List<MeaningItemVo> defaultMeaningItems = new ArrayList<>();
        for (MeaningItemVo meaningItemVo : destWordVo.getMeaningItems()) {
            DictVo dict = meaningItemVo.getDict();
            if (dict == null) { // 释义不属于任何特定单词书，则该释义是缺省释义
                defaultMeaningItems.add(meaningItemVo);
            } else if (dictIds.contains(dict.getId())) {
                // 尝试查找现有的具有相同词性的释义项
                MeaningItemVo existingItemWithSameCixing = null;
                for (MeaningItemVo itemVo : meaningItemVos) {
                    if (itemVo.getCiXing().equals(meaningItemVo.getCiXing())) {
                        existingItemWithSameCixing = itemVo;
                    }
                }

                if (existingItemWithSameCixing != null) { // 融合相同词性的释义项
                    LinkedHashSet<String> partsSet = new LinkedHashSet<>();
                    String[] parts = existingItemWithSameCixing.getMeaning().split("[;|；]");
                    partsSet.addAll(Arrays.asList(parts));
                    parts = meaningItemVo.getMeaning().split("[;|；]");
                    partsSet.addAll(Arrays.asList(parts));
                    StringBuilder sb = new StringBuilder();
                    LinkedHashSet<String> addedPartItems = new LinkedHashSet<>(); // 用于去掉重复释义
                    for (String part : partsSet) {
                        String[] partItems = part.split("[，|,]");
                        List<String> purifiedPartItems = Arrays.stream(partItems).map(item -> item.trim())
                                .filter(item -> !addedPartItems.contains(item)).collect(Collectors.toList());
                        if (!purifiedPartItems.isEmpty()) {
                            sb.append(purifiedPartItems.stream().collect(Collectors.joining("，"))).append("；");
                            addedPartItems.addAll(purifiedPartItems);
                        }
                    }
                    sb.deleteCharAt(sb.length() - 1);
                    MeaningItemVo mergedItem = new MeaningItemVo(existingItemWithSameCixing.getCiXing(), sb.toString());
                    if (existingItemWithSameCixing.getSynonyms() != null || meaningItemVo.getSynonyms() != null) {
                        HashSet<SynonymVo> synonyms = new HashSet<>();
                        if (existingItemWithSameCixing.getSynonyms() != null) {
                            synonyms.addAll(existingItemWithSameCixing.getSynonyms());
                        }
                        if (meaningItemVo.getSynonyms() != null) {
                            synonyms.addAll(meaningItemVo.getSynonyms());
                        }
                        mergedItem.setSynonyms(new ArrayList<>(synonyms));
                    }
                    meaningItemVos.remove(existingItemWithSameCixing);
                    meaningItemVos.add(mergedItem);
                } else { // 添加释义项
                    meaningItemVos.add(meaningItemVo);
                }
            }
        }

        if (meaningItemVos.isEmpty() && !defaultMeaningItems.isEmpty()) {
            meaningItemVos.addAll(defaultMeaningItems);
        }

        if (!meaningItemVos.isEmpty()) {
            destWordVo.setMeaningItems(meaningItemVos);
            destWordVo.setMeaningStr(null); // 通过置为null的方式刷新meaningStr
        }

        return destWordVo;
    }

    /**
     * 根据指定的单词书，对WordVo进行收缩（去除指定单词书范围之外的释义项）
     *
     * @param wordVo
     * @param selectedDictVos
     * @return
     */
    public static WordVo shrinkWordVo(final WordVo srcWordVo, List<Dict> dicts, final int maxSentenceCount,
            boolean removeSimilarWords) {
        Set<String> dictIds = new HashSet<>(dicts.size());
        for (Dict dict : dicts) {
            dictIds.add(dict.getId());
        }
        return shrinkWordVo(srcWordVo, dictIds, maxSentenceCount, removeSimilarWords);
    }

    /**
     * 根据指定的单词书，对WordVo进行收缩（去除指定单词书范围之外的释义项）
     *
     * @param wordVo
     * @param selectedDictVos
     * @return
     */
    public static WordVo shrinkWordVo2(WordVo srcWordVo, List<DictVo> dicts, final int maxSentenceCount,
            boolean removeSimilarWords) {
        Set<String> dictIds = new HashSet<>(dicts.size());
        for (DictVo dict : dicts) {
            dictIds.add(dict.getId());
        }
        return shrinkWordVo(srcWordVo, dictIds, maxSentenceCount, removeSimilarWords);
    }

    /**
     * 收缩wordVo，只包含缺省的释义项
     *
     * @param srcWordVo
     * @return
     */
    public static WordVo shrinkWordVo(WordVo srcWordVo, final int maxSentenceCount, boolean removeSimilarWords) {
        return shrinkWordVo(srcWordVo, new ArrayList<>(), maxSentenceCount, removeSimilarWords);
    }

    /**
     * 收缩wordVo，但保留所有释义项（包含通用释义和各词书释义）。
     * 仅做浅层复制与可选移除形近词，避免传输冗余。
     */
    public static WordVo shrinkWordVoKeepAll(WordVo srcWordVo, final int maxSentenceCount, boolean removeSimilarWords) {
        WordVo destWordVo = new WordVo();
        org.springframework.beans.BeanUtils.copyProperties(srcWordVo, destWordVo, "meaningItems", "similarWords");

        // 复制所有 meaningItems（不做词书过滤）
        if (srcWordVo.getMeaningItems() != null) {
            destWordVo.setMeaningItems(shrinkMeanItems(srcWordVo.getMeaningItems()));
            // 确保例句可发音：补全缺失的 englishDigest
            for (MeaningItemVo mi : destWordVo.getMeaningItems()) {
                if (mi.getSentences() != null) {
                    for (SentenceVo s : mi.getSentences()) {
                        if (s.getEnglishDigest() == null || s.getEnglishDigest().isEmpty()) {
                            s.setEnglishDigest(makeSentenceDigest(s.getEnglish()));
                        }
                    }
                }
            }
        }

        // 复制 similarWords（可选移除），用于前端展示形近词
        if (!removeSimilarWords && srcWordVo.getSimilarWords() != null) {
            List<WordVo> similarWords = new ArrayList<>(srcWordVo.getSimilarWords().size());
            destWordVo.setSimilarWords(similarWords);
            for (WordVo sw : srcWordVo.getSimilarWords()) {
                WordVo copy = new WordVo();
                org.springframework.beans.BeanUtils.copyProperties(sw, copy, "meaningItems");
                if (sw.getMeaningItems() != null) {
                    copy.setMeaningItems(shrinkMeanItems(sw.getMeaningItems()));
                }
                similarWords.add(copy);
            }
        }

        return destWordVo;
    }

    public static void sleep(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            log.error("sleep error", e);
        }
    }

    public static boolean isStringContainsIn(String str, String[] strings) {
        for (String string : strings) {
            if (string.equals(str)) {
                return true;
            }
        }
        return false;
    }

    public static List<MeaningItemVo> shrinkMeaningItemVos(final List<MeaningItemVo> src, String[] excludeFields) {
        List<MeaningItemVo> dest = new ArrayList<>(src.size());
        for (final MeaningItemVo srcVo : src) {
            MeaningItemVo destVo = new MeaningItemVo();
            BeanUtils.copyProperties(srcVo, destVo, excludeFields);
            dest.add(destVo);
        }
        return dest;
    }

    public static List<SentenceVo> shrinkSentenceVos(final List<SentenceVo> src, String[] fieldsToRemove) {
        List<SentenceVo> destVos = new ArrayList<>(src.size());
        for (final SentenceVo srcVo : src) {
            SentenceVo destVo = new SentenceVo();
            BeanUtils.copyProperties(srcVo, destVo, fieldsToRemove);
            destVos.add(destVo);
        }
        return destVos;
    }

    /**
     * 获取一个句子对应的前3个用户生成翻译
     *
     * @return
     */
    public static List<WordShortDescChineseVo> getWordShortDescChineses(Word word, final int count) {

        // 排序，被点赞绝对次数多的排在前面
        List<WordShortDescChinese> diyItems = word.getWordShortDescChineses();
        if (diyItems == null || diyItems.isEmpty()) {
            return new ArrayList<>(0);
        }
        sortShortDescChineses(diyItems);

        int total = diyItems.size();
        total = Math.min(total, count);
        List<WordShortDescChineseVo> diyItemVOs = new ArrayList<>(total);
        for (int i = 0; i < total; i++) {
            WordShortDescChinese po = diyItems.get(i);
            WordShortDescChineseVo vo = beidanci.service.util.BeanUtils.makeVo(po, WordShortDescChineseVo.class,
                    new String[] { "invitedBy", "word", "userGames", "studyGroups" });
            UserVo author = new UserVo();
            author.setDisplayNickName(po.getAuthor().getDisplayNickName());
            author.setUserName(po.getAuthor().getUserName());
            vo.setAuthor(author);

            diyItemVOs.add(vo);
        }

        return diyItemVOs;
    }

    public static void sortShortDescChineses(List<WordShortDescChinese> wordImages) {
        if (wordImages == null || wordImages.isEmpty()) {
            return;
        }
        Collections.sort(wordImages, (WordShortDescChinese o1, WordShortDescChinese o2) -> {
            Integer hand1Obj = o1.getHand();
            Integer foot1Obj = o1.getFoot();
            Integer hand2Obj = o2.getHand();
            Integer foot2Obj = o2.getFoot();
            int hand1 = hand1Obj == null ? 0 : hand1Obj;
            int foot1 = foot1Obj == null ? 0 : foot1Obj;
            int hand2 = hand2Obj == null ? 0 : hand2Obj;
            int foot2 = foot2Obj == null ? 0 : foot2Obj;
            int score1 = hand1 - foot1;
            int score2 = hand2 - foot2;
            if (score1 == score2) {
                long t1 = o1.getCreateTime() == null ? 0L : o1.getCreateTime().getTime();
                long t2 = o2.getCreateTime() == null ? 0L : o2.getCreateTime().getTime();
                return (int) (t2 - t1);
            } else {
                return score2 - score1;
            }
        });
    }

    public static PagedResults<DictWordVo> makePagedDictWordVos(PagedResults<DictWord> dictWords, WordCache wordCache) {
        List<DictWordVo> vos = new ArrayList<>(dictWords.getTotal());
        PagedResults<DictWordVo> pagedVos = new PagedResults<>(dictWords.getTotal(), vos);
        for (DictWord dictWord : dictWords.getRows()) {
            DictWordVo vo = beidanci.service.util.BeanUtils.makeVo(dictWord, DictWordVo.class,
                    new String[] { "dict", "synonyms", "similarWords", "word" });
            vo.setWord(dictWord.getWordVo(wordCache, new String[] {
                    "SynonymVo.meaningItem", "SynonymVo.word", "similarWords", "DictVo.dictWords" }));
            vos.add(vo);
        }
        return pagedVos;
    }

    /**
     * 获取两个时间之间的相隔的天数
     *
     * @param date1
     * @param date2
     * @return
     */
    public static int daysBetween(Date date1, Date date2) {
        long time1 = getPureDate(date1).getTime();
        long time2 = getPureDate(date2).getTime();
        long between_days = (time2 - time1) / (1000 * 3600 * 24);
        return (int) between_days;
    }

    public static void main(String[] args) throws Exception {
        sendEmailToNnbdcCustomerSerivce("test", "测试");
    }

    public static String uuid() {
        return UUID.randomUUID().toString().replaceAll("-", "");
    }

}
