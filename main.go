package main

import (
	"archive/zip"
	"fmt"
	"io"
	"io/ioutil"
	"math/rand"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/sirupsen/logrus"
)

var log = logrus.New()

const RESULT = "results/"
const TEMPLATE = "templates/"
const TMP = "temp/"

func SetupLogger() {
	// 设置日志格式
	log.Formatter = &logrus.TextFormatter{}

	// 设置日志输出到文件
	logFile, err := os.OpenFile("app.log", os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0666)
	if err == nil {
		log.Out = logFile
	} else {
		log.Info("Failed to log to file, using default stderr")
	}
}

func main() {
	// 启动一个 Goroutine 执行清空任务
	go clearTempFolder()
	SetupLogger()
	r := gin.Default()

	r.LoadHTMLFiles("index.html")

	r.GET("/", func(c *gin.Context) {
		// 读取uploads文件夹下的所有文件
		files, err := readFilesInDirectory(TEMPLATE)
		if err != nil {
			c.String(http.StatusInternalServerError, "Failed to read directory")
			return
		}
		c.HTML(200, "index.html", gin.H{
			"Files": files,
		})
	})

	r.POST("/upload", handleFileUpload)

	// 处理文件下载
	r.GET("/download/:filename", func(c *gin.Context) {
		filename := c.Param("filename")
		log.Info(fmt.Sprintf("Download %s", TEMPLATE+filename))
		file, err := os.Open(TEMPLATE + filename)
		if err != nil {
			c.String(http.StatusNotFound, "Filed to find file")
			return
		}
		defer file.Close()

		// 获取文件信息
		fileInfo, err := file.Stat()
		if err != nil {
			c.String(http.StatusInternalServerError, "Failed to get info of file")
			return
		}

		// 设置 HTTP 头，指示浏览器下载文件
		c.Header("Content-Description", "File Transfer")
		c.Header("Content-Transfer-Encoding", "binary")
		c.Header("Content-Disposition", "attachment; filename="+filename)
		c.Header("Content-Type", "application/octet-stream")
		c.Header("Content-Length", string(rune(fileInfo.Size())))

		// 将文件内容复制到响应体
		io.Copy(c.Writer, file)
	})

	r.Run(":8080")
	// 这里防止主 Goroutine 退出
	select {}
}

func handleFileUpload(c *gin.Context) {
	file, header, err := c.Request.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	defer file.Close()

	// 创建一个临时目录来存储上传的文件
	if _, err := os.Stat(TMP); os.IsNotExist(err) {
		os.Mkdir(TMP, os.ModePerm)
	}

	// 将上传的文件保存到临时目录
	filePath := filepath.Join(TMP, header.Filename)
	out, err := os.Create(filePath)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer out.Close()
	_, err = io.Copy(out, file)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// 解压文件
	unzipDir := filepath.Join(TMP, "./")
	err = unzip(filePath, unzipDir)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	fileBase := filepath.Base(filePath)
	// 获取文件夹名
	folderName := fileBase[:len(fileBase)-len(filepath.Ext(fileBase))]
	// 执行Movescanner命令
	randomResultFileName, err := executeMovescanner(filepath.Join(unzipDir, folderName))
	if err != nil {
		c.String(500, "Command execution error")
		return
	}

	result, _ := processJSON(RESULT + randomResultFileName)
	pageResult := fmt.Sprintf(`
	<!DOCTYPE html>
	<html>
	<head>
		<title>JSON Data</title>
	</head>
	<body>
		<h1>JSON Data:</h1>
		<pre id="json-data">%s</pre>
		
		<script>
			// 使用JavaScript将JSON数据格式化并在网页上展示
			var jsonData = JSON.parse(document.getElementById('json-data').textContent);
			document.getElementById('json-data').textContent = JSON.stringify(jsonData, null, 2);
		</script>
	</body>
	</html>`, result)

	c.Header("Content-Type", "text/html; charset=utf-8")
	c.String(http.StatusOK, pageResult)
}

type Data struct {
	Message string `json:"message"`
}

func processJSON(resultFile string) ([]byte, error) {
	data, err := ioutil.ReadFile(resultFile)
	if err != nil {
		log.Error(fmt.Sprintf("Faild to read %s", resultFile))
	}
	return data, err
}

func unzip(src, dest string) error {
	r, err := zip.OpenReader(src)
	if err != nil {
		return err
	}
	defer r.Close()

	for _, f := range r.File {
		rc, err := f.Open()
		if err != nil {
			return err
		}
		defer rc.Close()

		path := filepath.Join(dest, f.Name)

		if f.FileInfo().IsDir() {
			os.MkdirAll(path, os.ModePerm)
		} else {
			if err = os.MkdirAll(filepath.Dir(path), os.ModePerm); err != nil {
				return err
			}
			f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE, os.ModePerm)
			if err != nil {
				return err
			}
			_, err = io.Copy(f, rc)
			if err != nil {
				return err
			}
			f.Close()
		}
	}
	return nil
}

func readFilesInDirectory(directory string) ([]os.FileInfo, error) {
	dir, err := os.ReadDir(directory)
	if err != nil {
		return nil, err
	}

	var files []os.FileInfo
	for _, entry := range dir {
		if entry.IsDir() {
			continue // Skip directories
		}

		fileInfo, err := entry.Info()
		if err != nil {
			return nil, err
		}

		files = append(files, fileInfo)
	}

	return files, nil
}

func executeMovescanner(inputDir string) (string, error) {
	// 随机生成结果文件 result.json
	rand.Seed(time.Now().UnixNano())
	randomFileName := generateRandomFileName(10) + ".json"
	result_json := RESULT + randomFileName

	// 上传的项目中必须包含 bytecode_modules 文件夹
	bytecodeDir := findBytecodeFolder(inputDir)

	// 运行 MoveScanner
	var MOVESCANNER = "./MoveScanner"
	if runtime.GOOS == "linux" {
		MOVESCANNER = "./MoveScanner"
	} else if runtime.GOOS == "darwin" {
		MOVESCANNER = "./MoveScanner_m1"
	}
	log.Info(fmt.Sprintf("./MoveScanner -p %s -n -o %s", bytecodeDir, result_json))
	movescannerCmd := exec.Command(MOVESCANNER, "-p", bytecodeDir, "-n", "-o", result_json)
	_, err := movescannerCmd.CombinedOutput()
	if err != nil {
		return "", err
	}
	return randomFileName, nil
}

func clearTempFolder() {
	for {
		// 获取当前时间
		now := time.Now()
		// 设置下一个小时的整点时间
		nextHour := now.Truncate(time.Hour).Add(time.Hour)
		// 计算下一个小时与当前时间的时间差
		duration := nextHour.Sub(now)
		// 等待到下一个小时
		time.Sleep(duration)
		// 清空 temp results 文件夹
		if err := clearDirectory(TMP); err != nil {
			log.Error(fmt.Sprintf("清空 temp 文件夹出错: %v\n", err))
		} else {
			log.Info("temp 文件夹已清空")
		}
		if err := clearDirectory(RESULT); err != nil {
			log.Error(fmt.Sprintf("清空 results 文件夹出错: %v\n", err))
		} else {
			log.Info("result 文件夹已清空")
		}
	}
}

func clearDirectory(path string) error {
	dir, err := os.ReadDir(path)
	if err != nil {
		return err
	}

	for _, entry := range dir {
		err := os.RemoveAll(path + "/" + entry.Name())
		if err != nil {
			return err
		}
	}

	return nil
}

func generateRandomFileName(fileNameLength int) string {
	// 生成一个随机的文件名
	const letterBytes = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

	b := make([]byte, fileNameLength)
	for i := range b {
		b[i] = letterBytes[rand.Intn(len(letterBytes))]
	}
	return string(b)
}

// findBytecodeFolder 递归查找名为 "bytecode_modules" 的文件夹
func findBytecodeFolder(dirPath string) string {
	files, err := os.ReadDir(dirPath)
	if err != nil {
		log.Error(fmt.Sprintf("Error reading directory: %v\n", err))
		return ""
	}

	// 遍历当前文件夹的内容
	for _, file := range files {
		// 如果是文件夹并且文件夹名称为 "bytecode"，返回该路径
		if file.IsDir() && file.Name() == "bytecode_modules" {
			return filepath.Join(dirPath, "bytecode_modules")
		}

		// 如果是子文件夹，继续递归查找
		if file.IsDir() {
			subDir := filepath.Join(dirPath, file.Name())
			found := findBytecodeFolder(subDir)
			if found != "" {
				return found
			}
		}
	}
	return ""
}
