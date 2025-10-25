package beidanci.api;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;

/**
 * 排序类型(正序/反序)
 */
@ApiModel(description = "排序类型(正序/反序)")
public enum SortType {
    @ApiModelProperty("正序")
    Positive,

    @ApiModelProperty("反序")
    Negative
}
