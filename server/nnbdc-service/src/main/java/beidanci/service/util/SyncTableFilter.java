package beidanci.service.util;

import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

import org.apache.commons.lang3.StringUtils;

/**
 * 端云同步的「表能力」过滤。
 *
 * 背景：客户端的「后端表名 → 本地表」映射是随安装包发布的常量，老包遇到不认识的新表会直接
 * 抛异常，整次同步（连带用户数据同步）都会失败。所以服务端只能给客户端下发它认识的表。
 *
 * 判断依据（按优先级）：
 * <ol>
 * <li>新客户端在请求头 {@code X-Supported-Tables} 里声明自己支持的表清单（由客户端映射表导出，
 *     不需要人工维护第二份），服务端按声明放行；</li>
 * <li>没声明的是老客户端，按其 {@code X-Client-Version}（verCode）与
 *     {@link #INTRODUCED_IN}（每张新增表首次获得客户端支持的版本）比对放行；</li>
 * <li>未登记的表 = 2026-08-20（线上 minVerCode=26082001）之前就存在的老表，
 *     在网老包必然都认识。</li>
 * </ol>
 */
public final class SyncTableFilter {

    /** 客户端声明自己支持哪些表（逗号分隔的后端表名） */
    public static final String SUPPORTED_TABLES_HEADER = "X-Supported-Tables";

    /** 客户端版本号（verCode）请求头 */
    public static final String CLIENT_VERSION_HEADER = "X-Client-Version";

    /**
     * 新增同步表 → 首次支持它的客户端 verCode。
     *
     * 新表上线时**必须**在这里登记：在对应客户端版本发布之前，先登记成
     * {@link Integer#MAX_VALUE}（任何老客户端都不发），版本发布后再改成真实的 verCode。
     * 漏登记会让老客户端收到不认识的新表，整次同步直接失败。
     *
     * 取值由客户端映射表（app/lib/util/utils.dart 的 remoteTableNameToLocal）进入各版本的
     * 时间确定，可用 {@code git show <版本提交>:app/lib/util/utils.dart} 核对。
     */
    private static final Map<String, Integer> INTRODUCED_IN = Map.of(
            "user_badge", 26091301,
            "word_core_image", 26092401,
            "user_pet_state", 26100201,
            "word_phrase", Integer.MAX_VALUE);

    private SyncTableFilter() {
    }

    /**
     * 该客户端是否认识这张表。
     *
     * @param table                 后端表名
     * @param supportedTablesHeader 客户端声明的表清单，逗号分隔；为空表示未声明的老客户端
     * @param clientVersion         客户端 verCode；解析不出（老包 / "NONE"）按 0 处理，只放行未登记的老表
     */
    public static boolean isSupported(String table, String supportedTablesHeader, int clientVersion) {
        if (StringUtils.isNotBlank(supportedTablesHeader)) {
            for (String declared : supportedTablesHeader.split(",")) {
                if (declared.trim().equals(table)) {
                    return true;
                }
            }
            return false;
        }
        Integer introducedIn = INTRODUCED_IN.get(table);
        return introducedIn == null || introducedIn <= clientVersion;
    }

    /** 过滤掉该客户端不认识的表的同步日志 */
    public static <T> List<T> filter(List<T> logs, String supportedTablesHeader, int clientVersion,
            Function<T, String> tableNameOf) {
        return logs.stream()
                .filter(log -> isSupported(tableNameOf.apply(log), supportedTablesHeader, clientVersion))
                .collect(Collectors.toList());
    }

    /** 解析 verCode，解析不出返回 0（视作最老的客户端） */
    public static int parseClientVersion(String clientVersionHeader) {
        if (StringUtils.isBlank(clientVersionHeader)) {
            return 0;
        }
        try {
            return Integer.parseInt(clientVersionHeader.trim());
        } catch (NumberFormatException e) {
            return 0;
        }
    }
}
