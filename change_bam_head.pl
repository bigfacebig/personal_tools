# 导入 -> 系统 package
use strict;
use warnings;
use File::Spec;
use Getopt::Long;

# 定义 -> 常量
use constant SCRIPTDIR => (File::Spec->splitpath(File::Spec->rel2abs($0)))[1];
use constant PWD => $ENV{"PWD"};

# 定义 -> 核心变量
my $samtools      = "/home/genesky/software/samtools/1.10/samtools";
my $sambamba      = "/home/genesky/software/sambamba/0.6.7/sambamba";


# 检测 -> 脚本输入
my ($input_bam, $output_bam, $dict, $chr_map, $keep_tmp, $if_help);
GetOptions(
    "input_bam|i=s"   => \$input_bam,
    "output_bam|o=s"  => \$output_bam,
    "dict|d=s"        => \$dict,
    "chr_map=s"       => \$chr_map,
    "keep_tmp!"       => \$keep_tmp,
    "help|h"          => \$if_help,
);
die help() if(defined $if_help or (not defined $input_bam or not defined $dict or not defined $output_bam or not defined $chr_map));
###################################################################### 主程序

# （1）读入dict信息、map信息
print "read map/dict file \n";
my %hashMap = read_map($chr_map, $dict);


# (2) bam 转 sam 并替换
print "replace head/chr \n";
my $bam_tmp = "$output_bam.tmp.bam";
open BAM_INPUT, "$samtools view -h $input_bam |";
open BAM_OUTPUT, "| $samtools view -b -o $bam_tmp   ";
my $is_SQ = 0;
while(<BAM_INPUT>)
{
    $_=~s/[\r\n]//g;
    my @datas = split /\t/, $_;
    if($datas[0] eq '@SQ' and $is_SQ == 0)
    {
        print BAM_OUTPUT $hashMap{'HEAD'};
        $is_SQ = 1;
        next;
    }
    if($datas[0] eq '@HD' or $datas[0] eq '@RG' or $datas[0] eq '@PG')
    {
        print BAM_OUTPUT "$_\n";
        next; 
    }
    next if($datas[0] eq '@SQ');  # 旧的头部不再需要

    ######## reads 处理
    $datas[2] =  $hashMap{'MAP'}{$datas[2]}  if(exists $hashMap{'MAP'}{$datas[2]});  # 比对染色体
    $datas[6] =  $hashMap{'MAP'}{$datas[6]}  if(exists $hashMap{'MAP'}{$datas[6]});  # matepair 染色体

    # 检查XA tag信息，因为里面也包含了染色体编号
    foreach my $col(11..$#datas)
    {
        next if($datas[$col] !~ /^XA:/);
        # XA格式示例：XA:Z:chr19,+110509,151M,2;chr15,-102463282,151M,2;
        my ($tmp1, $tmp2, $map_info_list) = split /:/, $datas[$col];

        $datas[$col] = "$tmp1:$tmp2:";
        foreach my $map_info(split /;/, $map_info_list)
        {
            my ($chr, $tmp3) = split /,/, $map_info, 2;
            $chr =  $hashMap{'MAP'}{$chr}  if(exists $hashMap{'MAP'}{$chr});
            $datas[$col] .= "$chr,$tmp3;";
        }
    }
    print BAM_OUTPUT (join "\t", @datas) . "\n";
}
close BAM_INPUT;
close BAM_OUTPUT;

# (3) 排序
system("$sambamba sort $bam_tmp -o  $output_bam");
system("rm $bam_tmp") if(not defined $keep_tmp);







###################################################################### 子函数

sub read_map{
    my $chr_map = shift @_;
    my $dict    = shift @_;

    my %hashMap;

    # 读入dict文件，记录头部、染色体信息
    open DICT, $dict;
    while(<DICT>)
    {
        $_=~s/[\r\n]//g;
        my ($title, $chr_info, $length_info, $tmp) = split /\t/, $_, 4;
        next if($title !~ /^\@SQ/);  # 只需要染色体信息数据
        my $chr = $chr_info;
           $chr=~s/^SN://;

        $hashMap{'HEAD'} .= "$title\t$chr_info\t$length_info\n";
        $hashMap{'CHR_NEW'}{$chr}++;
    }
    close DICT;

    # 读取映射关系
    open MAP, $chr_map;
    while(<MAP>)
    {
        $_=~s/[\r\n]//g;
        my ($input_chr, $output_chr) = split /\t/, $_;
        die "[ERROR] chr_map文件里的映射染色体编号 '$output_chr' 无法匹配dict文件 $dict\n" if(not exists $hashMap{"CHR_NEW"}{$output_chr});
        $hashMap{'MAP'}{$input_chr} = $output_chr;
    }
    close MAP;
    return %hashMap;
}

sub help{
    my $info = "
Program: change bam head， 修改bam文件染色体信息
Version: 2019-02-28
Contact: 129 甘斌

Usage:   perl ".(File::Spec->splitpath(File::Spec->rel2abs($0)))[2]." [options]

Options:
        [必填]
         --input_bam/-i      输入bam文件
         --dict/-d           目标参考基因组dict文件,例如：/home/genesky/database/ucsc/hg19_modify/genome/hg19_modify.dict
         --chr_map           染色体编号映射关系，两列数据，没有表头，第一列是input_bam中的染色体名称，第二列是对应dict文件中的染色体名称
         --output_bam/-o     输出bam文件

        [选填] 
         --keep_tmp          保留替换过程中的中间文件。默认删除。中间文件是 output_bam.tmp.bam
         --help/-h           查看帮助文档
    \n";
    return $info;
}

 