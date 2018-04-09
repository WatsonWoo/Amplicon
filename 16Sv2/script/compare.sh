#!/bin/bash

# 模式设置 遇到错误终止流程 Stop when error
set -e 

# 默认参数 Default parameter
input=result/otutab.txt
# 统计方法，默认edgeR基于负二项分布的检验，可选wilcoxon秩和检验，也叫‘Mann-Whitney’ test.
method="edgeR"
design=doc/design.txt
g1=groupID
g1_list=''
compare=doc/compare.txt
output=result/compare/
execute=TRUE
order=FALSE
pvaule=0.01
FDR=0.05
fold_change=1.3
abundance_threshold=0.0005

# 脚本功能描述 Function for script description and usage
usage()
{
cat <<EOF >&2
Usage:
-------------------------------------------------------------------------------
Filename:    compare.sh
Version:     1.0
Date:        2018/4/7
Author:      Yong-Xin Liu
Email:       metagenome@126.com
Website:     https://blog.csdn.net/woodcorpse
Description: Group compare by edgeR or wilcon.test
Notes:       Input OTU table mustbe in raw reads counts
-------------------------------------------------------------------------------
Copyright:   2018 (c) Yong-Xin Liu
License:     GPL
If used this script, please cited:
Zhang, J., Zhang, N., Liu, Y.X., Zhang, X., Hu, B., Qin, Y., Xu, H., Wang, H., Guo, X., Qian, J., et al. (2018).
Root microbiota shift in rice correlates with resident time in the field and developmental stage. Sci China Life Sci 61, 
https://doi.org/10.1007/s11427-018-9284-4
-------------------------------------------------------------------------------
Version 1.0 2018/4/7
Group compare by edgeR or wilcon.test, input OTU table mustbe in raw reads counts
# All input and output should be in default directory, or give relative or absolute path by -i/-d

# Input files: design.txt, otutab.txt

# 1. 实验设计 doc/design.txt, SampleID and groupID column is needed
#SampleID	BarcodeSequence	LinkerPrimerSequence	ReversePrimer	groupID	genotype
GroupAr1	ACGCTCGACA	AACMGGATTAGATACCCKG	ACGTCATCCCCACCTTCC	GroupA	WT
GroupAr2	ATCAGACACG	AACMGGATTAGATACCCKG	ACGTCATCCCCACCTTCC	GroupA	WT

# 2. 标准化物种丰度表 result/tax/sum_*.txt, calculate by usearch10 -tax_div
#OTU ID ACT1KDr1        ACT1KDr10       ACT1KDr11       ACT1KDr13   
OTU_1   6898    4153    5775    1562    4774    4346    6469    4328
OTU_10  1085    524     948     349     1000    741     1214    739 

# Output file
1. OTUs with pvalue & FDR & fold change
2. Signifcantly abundance OTU.

OPTIONS:
	-c compare list file, default doc/compare.txt
	-d design for each samples, default doc/design.txt
	-e execuate Rscript, default TRUE
	-i OTU table in reads counts, default result/otutab.txt
	-m statistics method, default edgeR, alternative wilcon
	-o output director, default result/tax/
	-p pvaule, default 0.01
	-q FDR/qvalue, default 0.05
	-s text size, default 7
	-w figure width, default 8
	-A group name
	-B group selected list, empty will not select
	-F fold change, default 1.3
	-O order of legend, default FALSE alphabet, set TRUE abundance
	-? show help of script

Example:
compare.sh -i ${input} -m '${method}' -d ${design} -A ${g1} -B '${g1_list}' -o ${output} -O ${order} -w ${width} -h ${height}

EOF
}


# 参数解析 Analysis parameter
while getopts "c:d:e:h:i:m:n:o:p:q:s:t:w:A:B:F:O:" OPTION
do
	case $OPTION in
		c)
			compare=$OPTARG
			;;
		d)
			design=$OPTARG
			;;
		e)
			execute=$OPTARG
			;;
		h)
			height=$OPTARG
			;;
		i)
			input=$OPTARG
			;;
		m)
			method=$OPTARG
			;;
		n)
			number=$OPTARG
			;;
		o)
			output=$OPTARG
			;;
		p)
			pvalue=$OPTARG
			;;
		q)
			FDR=$OPTARG
			;;
		s)
			text_size=$OPTARG
			;;
		t)
			abundance_threshold=$OPTARG
			;;
		w)
			width=$OPTARG
			;;
		A)
			g1=$OPTARG
			;;
		B)
			g1_list=$OPTARG
			select1=TRUE
			;;
		F)
			foldchange=$OPTARG
			;;
		O)
			order=$OPTARG
			;;
		?)
			usage
			exit 1
			;;
	esac
done

# 当选择列表为空时，关闭实验设计筛选
if [ ${g1_list} == ""]; then
	select1=FALSE
fi

# 建立脚本目录
mkdir -p script

# 开始写R统计绘图脚本
cat <<END >script/compare.R
#!/usr/bin/env Rscript
# 
# Copyright 2016-2018 Yong-Xin Liu <metagenome@126.com>

# If used this script, please cited:
#   Zhang, J., Zhang, N., Liu, Y.X., Zhang, X., Hu, B., Qin, Y., Xu, H., Wang, H., Guo, X., Qian, J., et al. (2018).
# Root microbiota shift in rice correlates with resident time in the field and developmental stage. Sci China Life Sci 61, 
# https://doi.org/10.1007/s11427-018-9284-4

# 手动运行脚本请，需要设置工作目录，使用 Ctrl+Shift+H 或 Session - Set Work Directory - Choose Directory / To Source File Location 设置工作目录



# 1.1 程序功能描述和主要步骤

# 程序功能：高通量测序reads counts值的组间比较并筛选
# Functions: Calculate pvalue and FDR for each OTUs by edgeR or wilcon
# Main steps: 
# - Reads data matrix and design
# - Calculate pvalue and FDR
# - Save result table in *_all/sig.txt

# 清空工作环境 Clean enviroment object
rm(list=ls()) 


# 2.1 安装CRAN来源常用包
site="https://mirrors.tuna.tsinghua.edu.cn/CRAN"
# 依赖包列表：参数解析、数据变换、绘图和开发包安装、安装依赖、ggplot主题
package_list = c("limma","ggplot2","pheatmap","dplyr","devtools")
# 判断R包加载是否成功来决定是否安装后再加载
for(p in package_list){
	if(!suppressWarnings(suppressMessages(require(p, character.only = TRUE, quietly = TRUE, warn.conflicts = FALSE)))){
		install.packages(p, repos=site)
		suppressWarnings(suppressMessages(library(p, character.only = TRUE, quietly = TRUE, warn.conflicts = FALSE)))
  }
}

# 2.2 安装bioconductor常用包
package_list = c("edgeR")
for(p in package_list){
	if(!suppressWarnings(suppressMessages(require(p, character.only = TRUE, quietly = TRUE, warn.conflicts = FALSE)))){
		source("https://bioconductor.org/biocLite.R")
		biocLite(p)
		suppressWarnings(suppressMessages(library(p, character.only = TRUE, quietly = TRUE, warn.conflicts = FALSE)))
	}
}

# 2.3 安装Github常用包
# 参数解析、数据变换、绘图和开发包安装
package_list = c("kassambara/ggpubr")
for(p in package_list){
	q=unlist(strsplit(p,split = "/"))[2]
	if(!suppressWarnings(suppressMessages(require(q, character.only = TRUE, quietly = TRUE, warn.conflicts = FALSE)))){
		install_github(p)
		suppressWarnings(suppressMessages(library(q, character.only = TRUE, quietly = TRUE, warn.conflicts = FALSE)))
	}
}


# 3. 读取输入文件

# 读取实验设计
design = read.table("${design}", header=T, row.names=1, sep="\t", comment.char="")
# 统一改实验列为group
design\$group = design\$${g1}

# 按实验组筛选 Select by manual set group
if ($select1){
	design = subset(design, group %in% c(${g1_list}))
# 调置组排序 Set group order
	design\$group  = factor(design\$group, levels=c(${g1_list}))
}

# 读取OTU表
otutab = read.table(paste("${input}", sep=""), header=T, row.names=1, sep="\t", comment.char="") 

# 实验设计与输入文件交叉筛选
idx = rownames(design) %in% colnames(otutab)
design = design[idx,]
otutab = otutab[,rownames(design)]

# 按丰度值按组中位数筛选OTU
# 标准化为比例，并转置
norm = t(otutab)/colSums(otutab,na=T)
# 筛选组信
grp = design[, "group", drop=F]
# 按行名合并
mat_t2 = merge(grp, norm, by="row.names")
mat_t2 = mat_t2[,-1]
# 按组求中位数
mat_mean = aggregate(mat_t2[,-1], by=mat_t2[1], FUN=median) # mean
mat_mean_final = do.call(rbind, mat_mean)[-1,]
geno = mat_mean\$group
colnames(mat_mean_final) = geno
# 按丰度按组中位数筛选
filtered = mat_mean_final[apply(mat_mean_final,1,max) > ${abundance_threshold}, ] # select OTU at least one sample > 0.1%
otutab = otutab[rownames(filtered),]

END

# 4. 循环对每个分类级统计与绘图


cat <<END >>script/compare.R

compare_DA = function(compare){
	# 筛选比较组
	group_list = as.vector(as.matrix(compare))
	idx = design\$group %in% group_list
	sub_design=design[idx,]
	sub_dat=as.matrix(otutab[,rownames(sub_design)])

	d = DGEList(counts=sub_dat,group=factor(sub_design\$group))
	d = calcNormFactors(d)
	# check samples is in right groups
	d\$samples 

	design.mat = model.matrix(~ 0 + factor(sub_design\$group))
	rownames(design.mat)=colnames(sub_dat)
	colnames(design.mat)=levels(factor(sub_design\$group))
	DAO = estimateDisp(d,design.mat)
	fit = glmFit(DAO,design.mat)
	SampAvsB=paste(group_list[1] ,"-", group_list[2], sep="")
	BvsA <- makeContrasts(contrasts = SampAvsB, levels=design.mat)
	lrt = glmLRT(fit,contrast=BvsA)
	nrDAO=as.data.frame(topTags(lrt, n=nrow(sub_dat)))

	# 整理数据格式
	nrDAO\$logFC=round(nrDAO\$logFC,3)
	nrDAO\$logCPM=round(nrDAO\$logCPM,3)
	nrDAO\$level = ifelse(nrDAO\$logFC>log2(${fold_change}) & nrDAO\$PValue<${pvalue} & nrDAO\$FDR<${FDR}, "Enriched",ifelse(nrDAO\$logFC<log2(${fold_change})*(-1) & nrDAO\$PValue<${pvalue} & nrDAO\$FDR<${FDR}, "Depleted","NotSig"))
	nrDAO\$level=factor(nrDAO\$level,levels = c("Enriched","Depleted","NotSig"))

	# Add MeanA and MeanB in percentage
	# normlization to percentage
	norm = t(t(sub_dat)/colSums(sub_dat,na=T))*100
	# check norm is right?
	colSums(norm)
	# calculate groupA mean
	A_list = subset(sub_design, group %in% group_list[1])
	A_norm = norm[, rownames(A_list)]
	A_mean = as.data.frame(rowMeans(A_norm))
	colnames(A_mean)=c("MeanA")
	# calculate groupB mean
	B_list = subset(sub_design, group %in% group_list[2])
	B_norm = norm[, rownames(B_list)]
	B_mean = as.data.frame(rowMeans(B_norm))
	colnames(B_mean)=c("MeanB")
	# merge and reorder
	Mean = round(cbind(A_mean, B_mean, A_norm, B_norm),3)
	Mean = Mean[rownames(nrDAO),]   
	output=cbind(nrDAO[,-3],Mean)

	# write all OTU for volcano plot and manhattan plot
	write.table(paste(SampAvsB, "\t",sep=""), file=paste("$output", SampAvsB, "_all.txt",sep=""), append = F, quote = F, eol = "", row.names = F, col.names = F)
	suppressWarnings(write.table(output,file=paste("$output", SampAvsB, "_all.txt",sep=""), append = T, quote = F, sep = '\t', row.names = T))

	# 计算上、下调OTUs数量，写入统计文件
	NoE= dim(output[output\$level=="Enriched",])[1]
	NoD= dim(output[output\$level=="Depleted",])[1]
	NoN= dim(output[output\$level=="NotSig",])[1]
	suppressWarnings(write.table(paste( SampAvsB, NoE, NoD, NoN, sep="\t"), file=paste("$output", "summary.txt",sep=""), append = T, quote = F, sep = '\t', row.names = F, col.names = F))

	output=output[output\$level!="NotSig",]
	# 保存筛选结果于sig.txt结尾文件中
	write.table(paste(SampAvsB, "\t",sep=""), file=paste("$output", SampAvsB, "_sig.txt",sep=""), append = F, quote = F, eol = "", row.names = F, col.names = F)
	suppressWarnings(write.table(output, file=paste("$output", SampAvsB, "_sig.txt",sep=""), append = T, quote = F, sep = '\t', row.names = T))
}


# 记录各组间上、下调数量
write.table("GroupAvsB\tEnriched\tDepleted\tNotSig\n", file=paste("$output", "summary.txt",sep=""), append = F, quote = F, eol = "", row.names = F, col.names = F)

# 如果没有比较文件，则自动全循环
if (!file.exists("${compare}")) {
	compare_data = as.vector(unique(sub_design\$group))
	len_compare_data = length(compare_data)
	for(i in 1:(len_compare_data-1)) {
		for(j in (i+1):len_compare_data) {
			tmp_compare = as.data.frame(cbind(sampA=compare_data[i],sampB=compare_data[j]))
			compare_DA(tmp_compare)
		}
	}
# 有比较文件，按设计比较
}else {
	compare_data = read.table("${compare}", sep="\t", check.names=F, quote='', comment.char="")
	colnames(compare_data) = c("sampA", "sampB")
	for(i in 1:dim(compare_data)[1]){
		compare_DA(compare_data[i,])
	}
}

END



# 执行脚本，脚本运行目录即工作目录(与脚本位置无关)
if test "${execute}" == "TRUE";
then
	mkdir -p ${output}
	Rscript script/compare.R
fi
