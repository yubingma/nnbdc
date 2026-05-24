package beidanci.service.controller;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import beidanci.api.Result;
import beidanci.api.model.ErrorReportVo;
import beidanci.service.bo.ErrorReportBo;
import beidanci.service.po.ErrorReport;

@RestController
public class GetErrorReport {
    @Autowired
    ErrorReportBo errorReportBo;

    @GetMapping("/getErrorReport.do")
    public Result<ErrorReportVo> handle(@RequestParam("id") String id) {
        ErrorReport report = errorReportBo.findById(id);
        if (report == null) {
            return Result.fail("报错记录不存在");
        }
        ErrorReportVo vo = new ErrorReportVo(
                report.getId(),
                report.getUser() != null ? report.getUser().getId() : null,
                report.getUser() != null ? report.getUser().getNickName() : null,
                report.getContent(),
                report.getWord(),
                report.getFixed() != null ? report.getFixed() : false,
                report.getImageFiles()
        );
        return Result.success(vo);
    }
}
