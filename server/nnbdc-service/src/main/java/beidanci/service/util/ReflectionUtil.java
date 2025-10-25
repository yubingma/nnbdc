/**
 *
 */
package beidanci.service.util;

import java.beans.BeanInfo;
import java.beans.IntrospectionException;
import java.beans.Introspector;
import java.beans.PropertyDescriptor;
import java.lang.reflect.InvocationTargetException;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * @author Yongrui Wang
 */
public class ReflectionUtil {
    private static final Logger log = LoggerFactory.getLogger(ReflectionUtil.class);

    public static Object getFieldValue(Object entity, String fieldName) {
        Object gettedValue = null;
        BeanInfo beanInfo;
        PropertyDescriptor[] propertyDescriptors;
        try {
            beanInfo = Introspector.getBeanInfo(entity.getClass());
            propertyDescriptors = beanInfo.getPropertyDescriptors();
            for (PropertyDescriptor propertyDescriptor : propertyDescriptors) {
                String displayName = propertyDescriptor.getDisplayName();
                if (displayName.equals(fieldName)) {
                    gettedValue = propertyDescriptor.getReadMethod().invoke(entity);
                    break;
                } else {
                    String[] fieldNameArray = fieldName.split("\\.");
                    if (0 != fieldNameArray.length && displayName.equals(fieldNameArray[0])) {
                        String str = fieldNameArray[0] + ".";
                        String subEntityFieldName = fieldName.replace(str, "");
                        Object subEntity = propertyDescriptor.getReadMethod().invoke(entity);
                        if (null != subEntity) {
                            gettedValue = getFieldValue(subEntity, subEntityFieldName);
                        }
                    }
                }
            }
        } catch (IntrospectionException | IllegalAccessException | IllegalArgumentException | InvocationTargetException e) {
            log.error("Error getting field value for field: " + fieldName + " - " + e.getMessage());
        }

        return gettedValue;
    }

    public static void setFieldValue(Object entity, String fieldName, Object value)
            throws IntrospectionException, IllegalArgumentException, IllegalAccessException, InvocationTargetException {
        BeanInfo beanInfo;
        PropertyDescriptor[] propertyDescriptors;

        if (null != fieldName) {
            beanInfo = Introspector.getBeanInfo(entity.getClass());
            propertyDescriptors = beanInfo.getPropertyDescriptors();
            for (PropertyDescriptor propertyDescriptor : propertyDescriptors) {
                if (propertyDescriptor.getDisplayName().equals(fieldName)) {
                    propertyDescriptor.getWriteMethod().invoke(entity, value);
                    break;
                }
            }
        }
    }

}
