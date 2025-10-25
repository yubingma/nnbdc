package beidanci.service.util;


import beidanci.api.model.Vo;

import java.util.List;

public class AnimalVo extends Vo {
    private String name;
    private Integer age;
    private AnimalVo partner;
    private List<AnimalVo> children;

    public List<AnimalVo> getChildren() {
        return children;
    }

    public void setChildren(List<AnimalVo> children) {
        this.children = children;
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public Integer getAge() {
        return age;
    }

    public void setAge(Integer age) {
        this.age = age;
    }

    public AnimalVo getPartner() {
        return partner;
    }

    public void setPartner(AnimalVo partner) {
        this.partner = partner;
    }

    @Override
    public String toString() {
        return "AnimalVo{" +
                "name='" + name + '\'' +
                ", age=" + age +
                ", partner=" + partner +
                ", children=" + children +
                '}';
    }
}
