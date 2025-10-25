package beidanci.service.util;

import java.io.Serializable;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.lang.reflect.ParameterizedType;
import java.lang.reflect.Type;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;

import javax.persistence.Id;

import org.hibernate.Hibernate;
import org.hibernate.proxy.HibernateProxy;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.util.StringUtils;

import com.esotericsoftware.reflectasm.MethodAccess;

import beidanci.api.Result;
import beidanci.api.model.PagedResults;
import beidanci.api.model.Vo;
import beidanci.service.po.Po;

/**
 * 本类用于把<code>Po</code>转换为<code>Vo</code>
 *
 * @author MaYubing
 */
public class BeanUtils {
    private static final Logger log = LoggerFactory.getLogger(BeanUtils.class);

    private static final Map<Class<?>, MethodAccess> methodMap = new ConcurrentHashMap<>();

    private static final Map<String, Integer> methodIndexMap = new ConcurrentHashMap<>();

    private static final Map<Class<?>, List<Field>> fieldMap = new ConcurrentHashMap<>();

    /**
     * 函数调用深度（用于检测无穷递归）
     */
    private static final ThreadLocal<Integer> callDeep = new ThreadLocal<>();
    private static final Integer MAX_CALL_DEEP = 50;// 最大允许函数调用深度

    /**
     * 由持久对象（PO）生成值对象（VO）。VO各字段值由PO同名字段复制而来，如果某字段本身也是VO，在复制过程中会由PO自动转换为VO。<br>
     * 本方法会递归转换子孙对象。<br>
     * 可以指定哪些字段（可以含VO类名）不需要复制，这样可以避免不必要的性能损失，也可以有效防止转换过程出现无穷递归。
     *
     * @param po
     * @param voClass
     * @return
     */
    public static <T extends Vo> T makeVo(Po po, Class<T> voClass, String[] excludeFields) {
        HashSet<String> excludes = excludeFields == null ? new HashSet<>() : new HashSet<>(Arrays.asList(excludeFields));
        callDeep.set(0);
        T vo = doMakeVo(po, voClass, excludes, "");
        assert (callDeep.get().equals(0));
        return vo;
    }

    public static <T extends Vo> T makeVo(Po po, Class<T> voClass) {
        return makeVo(po, voClass, null);
    }

    public static <T extends Vo> List<T> makeVos(List<? extends Po> pos, Class<T> voClass, String[] excludeFields) {
        List<T> vos = new ArrayList<>(100);
        for (Po po : pos) {
            T vo = makeVo(po, voClass, excludeFields);
            vos.add(vo);
        }
        return vos;
    }

    public static <T extends Vo> PagedResults<T> makePagedVos(PagedResults<? extends Po> pos, Class<T> voClass,
                                                              String[] excludeFields) {
        List<T> vos = makeVos(pos.getRows(), voClass, excludeFields);
        PagedResults<T> pagedVos = new PagedResults<>(pos.getTotal(), vos);
        return pagedVos;
    }

    public static <T extends Vo> Result<T> makeVoResult(Result<? extends Po> poResult, Class<T> voClass,
                                                        String[] excludeFields) {
        T vo = makeVo(poResult.getData(), voClass, excludeFields);
        return new Result<>(poResult.isSuccess(), poResult.getMsg(), vo);
    }

    public static <T extends Vo> Result<List<T>> makeVosResult(Result<List<? extends Po>> posResult, Class<T> voClass,
                                                               String[] excludeFields) {
        List<T> vos = BeanUtils.makeVos(posResult.getData(), voClass, excludeFields);
        Result<List<T>> result2 = new Result<>(posResult.isSuccess(), posResult.getMsg(), vos);
        return result2;
    }

    @SuppressWarnings({"deprecation", "unchecked"})
    private static <T extends Vo> T doMakeVo(Po po, Class<T> voClass, HashSet<String> excludeFields, String fullFieldName) {
        if (po == null) {
            return null;
        }

        // 进入函数，增加调用深度
        callDeep.set(callDeep.get() + 1);
        if (callDeep.get() > MAX_CALL_DEEP) {
            throw new RuntimeException("函数调用深度大于" + MAX_CALL_DEEP + ": " + fullFieldName);
        }

        T vo;
        try {
            vo = voClass.newInstance();
        } catch (InstantiationException | IllegalAccessException e) {
            throw new RuntimeException(e);
        }

        MethodAccess destMethodAccess = methodMap.get(voClass);
        if (destMethodAccess == null) {
            destMethodAccess = cache(vo);
        }

        // 由于PO对象可能为动态包装的Proxy(Hibernate会把lazy load的属性包装为Proxy)，所以需要特殊处理
        String poClassName = po.getClass().getName();
        int suffix = poClassName.indexOf("_$$");
        if (suffix != -1) {
            po = initializeAndUnproxy(po);
        }
        MethodAccess srcMethodAccess = methodMap.get(po.getClass());
        if (srcMethodAccess == null) {
            srcMethodAccess = cache(po);
        }

        List<Field> fieldList = fieldMap.get(voClass);
        for (Field field : fieldList) {
            try {
                final String fullName = fullFieldName + "." + field.getName();
                if (isFieldExcluded(voClass.getSimpleName(), field.getName(), fullName, excludeFields)) {
                    continue;
                }
                String fieldName = StringUtils.capitalize(field.getName());
                String getKey = po.getClass().getName() + "." + "get" + fieldName;
                String setkey = vo.getClass().getName() + "." + "set" + fieldName;
                Integer getIndex = methodIndexMap.get(getKey);
                if (getIndex != null) {
                    int setIndex = methodIndexMap.get(setkey);
                    Object srcValue = srcMethodAccess.invoke(po, getIndex);

                    Object destValue = srcValue;
                    if (Vo.class.isAssignableFrom(field.getType())) {
                        if (log.isTraceEnabled()) {
                            log.trace(String.format("voClass[%s] fieldName[%s] fieldType[%s]", voClass.getSimpleName(),
                                    field.getName(), field.getType().getSimpleName()));
                        }
                        if (srcValue != null && !(srcValue instanceof Po)) {
                            throw new RuntimeException(String.format("期望是Po但实际是%s--", srcValue.getClass())
                                    + String.format("voClass[%s] fieldName[%s] fieldType[%s]", voClass.getSimpleName(),
                                    field.getName(), field.getType().getSimpleName()));
                        }
                        destValue = doMakeVo((Po) srcValue, (Class<T>) field.getType(), excludeFields, fullName);
                    } else if (List.class.isAssignableFrom(field.getType())) {
                        Type fc = field.getGenericType();
                        if (fc instanceof ParameterizedType pt) {
                            Class<?> genericClazz = (Class<?>) pt.getActualTypeArguments()[0];
                            if (log.isTraceEnabled()) {
                                log.trace(String.format("voClass[%s] fieldName[%s] fieldType[%s] genericClazz[%s]",
                                        voClass.getSimpleName(), field.getName(), field.getType().getSimpleName(),
                                        genericClazz.getSimpleName()));
                            }
                            List<Po> srcList = (List<Po>) srcValue;
                            destValue = new ArrayList<>();
                            if (srcList != null) {
                                if (!Vo.class.isAssignableFrom(genericClazz)) {
                                    throw new RuntimeException("List generic type is not a Vo: " + genericClazz.getName());
                                }
                                Class<? extends Vo> voType = (Class<? extends Vo>) genericClazz;
                                for (Po srcListItem : srcList) {
                                    Vo childVo = doMakeVo(srcListItem, voType, excludeFields, fullName);
                                    ((List<Vo>) destValue).add(childVo);
                                }
                            }
                        }
                    }

                    destMethodAccess.invoke(vo, setIndex, destValue);
                }
            } catch (RuntimeException e) {
                log.error(String.format("处理%s.%s时发生异常", poClassName, field.getName()));
                throw e;
            }
        }

        // 离开函数，减少调用深度
        callDeep.set(callDeep.get() - 1);
        return vo;
    }

    /**
     * 利用反射生成指定对象的属性值字符串(只包含有get方法的那些属性)
     *
     * @return
     */
    public static String beanToStr(Object bean) {
        MethodAccess srcMethodAccess = methodMap.get(bean.getClass());
        if (srcMethodAccess == null) {
            srcMethodAccess = cache(bean);
        }

        StringBuilder sb = new StringBuilder();
        List<Field> fieldList = fieldMap.get(bean.getClass());
        for (Field field : fieldList) {
            String fieldName = StringUtils.capitalize(field.getName());
            String getKey = bean.getClass().getName() + "." + "get" + fieldName;
            Integer getIndex = methodIndexMap.get(getKey);
            if (getIndex != null) {
                Object fieldValue = srcMethodAccess.invoke(bean, getIndex);
                sb.append(fieldName);
                sb.append("=");
                sb.append(fieldValue);
                sb.append("\n");
            }
        }
        return sb.toString();
    }

    /**
     * 获取指定类拥有的属性
     *
     * @param clazz
     * @param recusive 为true表示也获取继承子祖先类的字段
     * @return
     */
    public static List<Field> getFields(Class<?> clazz, boolean recusive) {
        // 本类的字段
        List<Field> allFields = new ArrayList<>();
        Field[] fields = clazz.getDeclaredFields();
        allFields.addAll(Arrays.asList(fields));

        if (recusive) {
            // 父类的字段
            Class<?> superclass = clazz.getSuperclass();
            fields = superclass.getDeclaredFields();
            Collections.addAll(allFields, fields);

            // 祖父类的字段
            Class<?> grandclass = superclass.getSuperclass();
            if (grandclass != null) {
                fields = grandclass.getDeclaredFields();
                allFields.addAll(Arrays.asList(fields));
            }
        }

        return allFields;
    }

    /**
     * 生成指定对象的MethodAccess并保存在缓存中。
     *
     * @return
     */
    private static MethodAccess cache(Object obj) {
        Class<? extends Object> clazz = obj.getClass();
        synchronized (methodMap) {
            MethodAccess methodAccess = methodMap.get(clazz);
            if (methodAccess == null) {
                log.info("caching " + clazz.getName());
                methodAccess = MethodAccess.get(clazz);

                // 缓冲字段及其get/set方法
                List<Field> allFields = getFields(clazz, true);
                List<Field> fieldList = new ArrayList<>(allFields.size());
                for (Field field : allFields) {
                    if ((Modifier.isPrivate(field.getModifiers()) || Modifier.isProtected(field.getModifiers())) && !Modifier.isStatic(field.getModifiers())) {// 非静态私有或保护变量
                        String fieldName = StringUtils.capitalize(field.getName());
                        if (!fieldName.startsWith("$$")) {
                            int getIndex = methodAccess.getIndex("get" + fieldName);
                            int setIndex = methodAccess.getIndex("set" + fieldName);
                            methodIndexMap.put(clazz.getName() + "." + "get" + fieldName, getIndex);
                            methodIndexMap.put(clazz.getName() + "." + "set" + fieldName, setIndex);
                            fieldList.add(field);
                        }
                    }
                }
                fieldMap.put(clazz, fieldList);

                // 缓冲get方法(不要求有相应的字段成员)
                for (Method method : clazz.getMethods()) {
                    String methodName = method.getName();
                    String cachedName = clazz.getName() + "." + methodName;
                    if (methodName.startsWith("get") && !methodName.equals("getClass")
                            && !methodIndexMap.containsKey(cachedName)) {
                        int getIndex = methodAccess.getIndex(methodName);
                        methodIndexMap.put(cachedName, getIndex);
                    }
                }

                methodMap.put(clazz, methodAccess);
            }
            return methodAccess;
        }
    }

    /**
     * 把Hibernate代理对象还原为源对象
     *
     * @param entity
     * @return
     */
    @SuppressWarnings("unchecked")
    public static <T> T initializeAndUnproxy(T entity) {
        if (entity == null) {
            throw new NullPointerException("Entity passed for initialization is null");
        }

        Hibernate.initialize(entity);
        if (entity instanceof HibernateProxy hibernateProxy) {
            entity = (T) hibernateProxy.getHibernateLazyInitializer().getImplementation();
        }
        return entity;
    }


    /**
     * 把对象的所有属性设为null, 除了指定的那些属性
     *
     * @param object
     * @throws IllegalAccessException
     * @throws IllegalArgumentException
     */
    public static void setPropertiesToNull(Object object, String[] excludeFields)
            throws IllegalArgumentException, IllegalAccessException {
        if (object == null) {
            return;
        }
        HashSet<String> excludes = new HashSet<>();
        excludes.addAll(Arrays.asList(excludeFields));
        Class<?> clazz = object.getClass();
        for (Field field : clazz.getDeclaredFields()) {
            if (!excludes.contains(field.getName()) && !((field.getModifiers() & Modifier.STATIC) == Modifier.STATIC)) {
                field.setAccessible(true);
                field.set(object, null);
            }
        }

        // 父类的字段
        Class<?> superclass = clazz.getSuperclass();
        for (Field field : superclass.getDeclaredFields()) {
            if (!excludes.contains(field.getName()) && !((field.getModifiers() & Modifier.STATIC) == Modifier.STATIC)) {
                field.setAccessible(true);
                field.set(object, null);
            }
        }

        // 祖父类的字段
        Class<?> grandclass = superclass.getSuperclass();
        for (Field field : grandclass.getDeclaredFields()) {
            if (!excludes.contains(field.getName()) && !((field.getModifiers() & Modifier.STATIC) == Modifier.STATIC)) {
                field.setAccessible(true);
                field.set(object, null);
            }
        }
    }

    /**
     * 利用反射获取指定PO对象的ID值
     *
     * @param po
     * @return
     * @throws IllegalAccessException
     * @throws IllegalArgumentException
     */
    public static Serializable getIdOfPo(Po po) throws IllegalArgumentException, IllegalAccessException {
        List<Field> fieldList = fieldMap.get(po.getClass());
        if (fieldList == null) {
            cache(po);
            fieldList = fieldMap.get(po.getClass());
            assert (fieldList != null);
        }
        for (Field field : fieldList) {
            if (field.isAnnotationPresent(Id.class)) {
                field.setAccessible(true);
                return (Serializable) field.get(po);
            }
        }
        throw new RuntimeException("指定PO对象没有定义ID字段");
    }

    /**
     * 判断指定类的指定字段是否应该被排除
     *
     * @param className
     * @param fieldName
     * @param excludeFields
     * @return
     */
    private static boolean isFieldExcluded(String className, String fieldName, String fullFieldName, HashSet<String> excludeFields) {
        int lastDotIndex = fullFieldName.lastIndexOf(".");
        final String path = fullFieldName.substring(0, lastDotIndex).replaceFirst("\\.", "");
        final String pureFieldName = fullFieldName.substring(lastDotIndex + 1);
        fullFieldName = fullFieldName.substring(1);

        // 判断字段是否被正向排除
        boolean excludeThisField =
                excludeFields.contains(fieldName)
                        || excludeFields.contains(fullFieldName)
                        || excludeFields.contains(new StringBuilder(className).append(".").append(fieldName).toString());
        if (excludeThisField) {
            return true;
        }

        // 判断字段是否被逆向排除(形如a.b.^f1,f2 或 A.^f1,f2)
        List<String> reverseRules = excludeFields.stream().filter(f -> {
            String path0;
            String pureFieldName0;
            int lastDotIndex0 = f.lastIndexOf(".");
            if (lastDotIndex0 == -1) {
                path0 = "";
                pureFieldName0 = f;
            } else {
                path0 = f.substring(0, lastDotIndex0);
                pureFieldName0 = f.substring(lastDotIndex0 + 1);
            }
            return (path0.equalsIgnoreCase(path) || className.equalsIgnoreCase(path0)) && pureFieldName0.startsWith("^");
        }).collect(Collectors.toList());
        for (String reverseRule : reverseRules) {
            int lastDotIndex0 = reverseRule.lastIndexOf(".");
            String reserveFields_ = reverseRule.substring(lastDotIndex0 + 2);
            Set<String> reserveFields = Arrays.stream(reserveFields_.split(",")).collect(Collectors.toSet());
            if (!reserveFields.contains(pureFieldName)) { // 匹配到任何一个反向排除规则，即表示该字段应该被排除
                return true;
            }
        }
        return false;
    }

    public static void main(String[] args) {
        Animal dog = new Animal("dog", 11);
        Animal cat = new Animal("cat", 3);
        Animal mouse = new Animal("mouse", 2);
        dog.setPartner(cat);
        List<Animal> children = new ArrayList<>();
        children.add(cat);
        children.add(mouse);
        dog.setChildren(children);
        AnimalVo dogVo = BeanUtils.makeVo(dog, AnimalVo.class, new String[]{"AnimalVo.^age,children"});
        System.out.println(dogVo);
    }

}
