from fastapi import FastAPI, File, UploadFile
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import os

app = FastAPI()

# 允许跨域请求
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def writeFile(path, file):
    content = file.read()
    with open(path, "wb") as f:
        f.write(content)
        f.flush()
        f.close()

@app.post("/uploadfile/")
async def uploadFile(file: UploadFile = File(...)):
    # print(file.filename)
    file_path = os.path.join(basePath, file.filename)
    # print(file_path)
    threadPool.submit(writeFile, file_path, file.file)
    return '保存成功'

def startSever(base_path, thread_pool):
    global basePath, threadPool
    basePath = os.path.abspath(base_path)
    threadPool = thread_pool
    uvicorn.run(app, host="192.168.1.85", port=8000, ssl_keyfile="./ssl.key", ssl_certfile="./ssl.crt")


if __name__ == "__main__":
    from concurrent.futures import ThreadPoolExecutor
    startSever('./', ThreadPoolExecutor(max_workers=3))
