package beidanci.service.controller;

import java.sql.SQLException;

import javax.naming.NamingException;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import beidanci.api.Result;
import beidanci.service.bo.ErrorReportBo;

@RestController
public class SaveErrorReport {
    @Autowired
    ErrorReportBo errorReportBo;


    @PostMapping("/saveErrorReport.do")
    public Result<String> handle(@RequestParam("word") String spell, @RequestParam("content") String content, String userId, @RequestParam("clientType") String clientType)
            throws SQLException, NamingException, ClassNotFoundException {
        return errorReportBo.saveErrorReport(spell, content, userId, clientType);
    }

}
