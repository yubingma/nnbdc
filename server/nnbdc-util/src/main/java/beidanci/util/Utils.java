package beidanci.util;

import java.io.DataOutputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Date;
import java.util.List;
import java.util.concurrent.TimeUnit;

public class Utils {

    public static String replaceDoubleSpace(String str) {
        while (str.contains("  ")) {
            str = str.replaceAll("  ", " ");
        }
        return str;
    }

    /**
     * 清楚字符串中多余的空格及制表符、回车等
     *
     * @return
     */
    public static String uniformString(String str) {
        str = str.replaceAll("\t", " ");
        str = str.replaceAll("\n", " ");
        str = replaceDoubleSpace(str);
        return str.trim();
    }

    public static String uniformSpellForFilename(String spell) {
        spell = spell.replaceAll("\\?", "").toLowerCase();
        spell = uniformString(spell);
        return spell;
    }

    public static String getFileNameOfWordSound(String spell) {
        spell = uniformSpellForFilename(spell);
        char firstChar = spell.substring(0, 1).toCharArray()[0];

        if (firstChar >= 'a' && firstChar <= 'z') {
            return firstChar + "/" + spell;
        } else {
            return "other" + "/" + spell;
        }
    }

    public static String purifySpell(String spell) {
        boolean isPhase = spell.trim().contains(" "); // 是否是短语
        if (isPhase) {
            return spell;
        }

        // 如果单词以逗号、句号等结束，首先将这些符号去掉
        while (spell.endsWith(",") || spell.endsWith("?") || spell.endsWith(".") || spell.endsWith("\"")
                || spell.endsWith("”") || spell.endsWith("'") || spell.endsWith(")") || spell.endsWith(":")
                || spell.endsWith("!") || spell.endsWith(";")) {
            spell = spell.substring(0, spell.length() - 1);
        }

        // 如果单词以引号、括号等开始，首先将这些符号去掉
        while (spell.startsWith("\"") || spell.startsWith("”") || spell.startsWith("'") || spell.startsWith("(")) {
            spell = spell.substring(1, spell.length());
        }

        return spell;
    }

    /**
     * 获取一个单词所有可能的变体形式
     *
     * @param spell
     * @return
     */
    public static List<String> getAllPossibleFormsOfWord(String spell) {
        List<String> words = new ArrayList<>();
        words.add(spell);
        words.add(spell + "s");
        words.add(spell + "es");
        words.add(spell + "’s");
        words.add(spell + "'s");
        if (spell.endsWith("y"))
            words.add(spell.substring(0, spell.length() - 1) + "ies");

        if (spell.endsWith("e"))
            words.add(spell + "d");
        else
            words.add(spell + "ed");

        if (spell.endsWith("e"))
            words.add(spell.substring(0, spell.length() - 1) + "ing");
        else
            words.add(spell + "ing");
        return words;
    }

    public static long getDifferenceDays(final Date d1, final Date d2) {
        if (d1 == null || d2 == null) {
            return Long.MAX_VALUE;
        }
        long diff = getPureDate(d2).getTime() - getPureDate(d1).getTime();
        return TimeUnit.DAYS.convert(diff, TimeUnit.MILLISECONDS);
    }

    public static Date getPureDate(final Date date) {
        Calendar rightNow = Calendar.getInstance();
        rightNow.clear();
        rightNow.setTime(date);
        rightNow.set(Calendar.HOUR_OF_DAY, 0);
        rightNow.set(Calendar.MINUTE, 0);
        rightNow.set(Calendar.SECOND, 0);
        rightNow.set(Calendar.MILLISECOND, 0);
        Date result = rightNow.getTime();

        return result;
    }

    /**
     * Criteria的list方法有可能直接返回Entity列表，也可能返回Object[]列表（Entity含在Object[]的某个元素中），
     * 此函数用于自动从list方法返回的列表中提取Entity列表。
     *
     * @param objects
     * @param clazz
     * @return
     */
    @SuppressWarnings("unchecked")
    public static <T> List<T> abstractEntityFromList(List<Object> objects, Class<T> clazz) {
        List<T> entities = new ArrayList<>(objects.size());
        if (!objects.isEmpty()) {
            Object firstObject = objects.get(0);

            boolean isEntity = clazz.isInstance(firstObject);
            int atIndex = -1;
            if (!isEntity) {
                for (int i = 0; i < ((Object[]) firstObject).length; i++) {
                    Object object = ((Object[]) firstObject)[i];
                    if (object.getClass() == clazz) {
                        atIndex = i;
                        break;
                    }
                }
            }
            for (Object object : objects) {
                if (isEntity) {
                    T entity = (T) object;
                    entities.add(entity);
                } else {
                    T entity = (T) ((Object[]) object)[atIndex];
                    entities.add(entity);
                }
            }
        }
        return entities;
    }

    public static void saveData2File(String fileName, byte[] data) throws IOException {
        try (DataOutputStream out = new DataOutputStream(new FileOutputStream(fileName))) {
            out.write(data);
        }
    }

    public static Date localDate2Date(LocalDate localDate) {
        ZonedDateTime zonedDateTime = localDate.atStartOfDay(ZoneId.systemDefault());
        return Date.from(zonedDateTime.toInstant());
    }


}
