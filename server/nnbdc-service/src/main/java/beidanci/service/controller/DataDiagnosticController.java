package beidanci.service.controller;

import beidanci.api.Result;
import beidanci.api.model.DiagnosticResultVo;
import beidanci.api.model.DataFixResultDto;
import beidanci.service.bo.DataDiagnosticBo;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

/**
 * 数据诊断控制器
 */
@RestController
public class DataDiagnosticController {

    @Autowired
    private DataDiagnosticBo dataDiagnosticBo;

    /**
     * 执行系统数据诊断
     */
    @GetMapping("/performSystemDiagnostic.do")
    public Result<DiagnosticResultVo> performSystemDiagnostic() {
        try {
            DiagnosticResultVo result = dataDiagnosticBo.performSystemDiagnostic();
            return Result.success(result);
        } catch (Exception e) {
            return Result.fail("系统数据诊断失败: " + e.getMessage());
        }
    }

    /**
     * 执行用户数据诊断
     */
    @GetMapping("/performUserDiagnostic.do")
    public Result<DiagnosticResultVo> performUserDiagnostic(@RequestParam("userId") String userId) {
        try {
            DiagnosticResultVo result = dataDiagnosticBo.performUserDiagnostic(userId);
            return Result.success(result);
        } catch (Exception e) {
            return Result.fail("用户数据诊断失败: " + e.getMessage());
        }
    }

    /**
     * 自动修复发现的问题
     */
    @PostMapping("/autoFixDataIssues.do")
    public Result<DataFixResultDto> autoFixDataIssues(@RequestBody DiagnosticResultVo diagnosticResult) {
        try {
            DataFixResultDto result = dataDiagnosticBo.autoFix(diagnosticResult);
            return Result.success(result);
        } catch (Exception e) {
            return Result.fail("自动修复失败: " + e.getMessage());
        }
    }
}
