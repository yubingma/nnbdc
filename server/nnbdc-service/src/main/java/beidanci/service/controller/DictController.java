package beidanci.service.controller;

import java.text.ParseException;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import beidanci.api.Result;
import beidanci.api.model.DictDto;
import beidanci.service.bo.DictBo;

@RestController
public class DictController {
    @Autowired
    private DictBo dictBo;

    /**
     * 获取词典基础信息（轻量接口，用于获取名称/ownerId 等）。
     * @throws ParseException 
     */
    @GetMapping("/getDictInfo.do")
    public Result<DictDto> getDictInfo(@RequestParam String dictId) throws ParseException {
        DictDto dictDto = dictBo.getDictDto(dictId);
        if (dictDto == null) {
            return Result.fail("词典不存在");
        }
        return Result.success(dictDto);
    }
}
