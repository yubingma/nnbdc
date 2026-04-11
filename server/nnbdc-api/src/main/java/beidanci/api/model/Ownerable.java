package beidanci.api.model;

/**
 * 具有归属权（拥有者）的实体或数据传输对象接口。
 * 实现此接口的类应能够提供其所有者的 ID。
 */
public interface Ownerable {
    /**
     * 获取数据持有者的唯一 ID。
     * 对于系统公共数据，通常返回系统管理员 ID (Constants.SYS_USER_SYS_ID)；
     * 对于用户私有数据，返回对应用户的 ID。
     *
     * @return 拥有者 ID
     */
    String getOwnerId();
}
