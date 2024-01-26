from seleniumwire import webdriver
import browser
import sever
import os
from threading import Thread
import time
from concurrent.futures import ThreadPoolExecutor

#executable_path='./chromedriver.exe'
browser = browser.Browser().browser;
threadPool = ThreadPoolExecutor(max_workers=6)

'''

3d虚拟
https://tapestry.cyark.org/content/{id}

'''
def getDec(id):
    url = 'https://www.cyark.org/projects/{}/overview'.format(id)
    browser.get(url)
    
def getModelFile(id, type):
    url = 'https://www.cyark.org/projects/{}/{}'.format(id, type)
    browser.get(url)
# def sever_thread(threadName, delay):

# sever.startSever()

# browser.get('https://www.cyark.org/projects/cliff-palace/tapestry2')
def startSever():
    sever_thread = Thread(target = sever.startSever)
    sever_thread.start('./model', threadPool)


