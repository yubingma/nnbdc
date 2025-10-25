package beidanci.service;

import beidanci.service.po.UuidPo;
import beidanci.service.util.Util;

public class UuidSetter {
    public static void setUuidIfNotPresent(Object entity) {
        if (entity instanceof UuidPo po) {
            if (po.getId() == null) {  // 如果 ID 为空，则生成 UUID
                po.setId(Util.uuid());
            }
        }
    }
}
