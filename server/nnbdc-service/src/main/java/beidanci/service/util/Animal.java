package beidanci.service.util;

import beidanci.service.po.Po;

import java.util.List;

public class Animal extends Po {
    private String name;
    private Integer age;
    private Animal partner;
    private List<Animal> children;

    public Animal(String name, int age) {
        this.name = name;
        this.age = age;
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

    public Animal getPartner() {
        return partner;
    }

    public void setPartner(Animal partner) {
        this.partner = partner;
    }

    public List<Animal> getChildren() {
        return children;
    }

    public void setChildren(List<Animal> children) {
        this.children = children;
    }
}
