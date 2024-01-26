from seleniumwire import webdriver

#executable_path='./chromedriver.exe'

# 80003c416f433f62a9ff3a05e5537460-v2.js
# 拦截器
def request_interceptor(request):
        if(request.url.endswith('80003c416f433f62a9ff3a05e5537460-v2.js')):
            with open('./80003c416f433f62a9ff3a05e5537460-v2.js', 'r') as file:
                request.create_response(
                    status_code = 200,
                    headers = {
                        'Access-Control-Allow-Origin': '*',
                        'Content-Type': 'application/javascript'
                        },
                    body = file.read()
                )
            print(request)


def response_interceptor(request, response):
        print('')
        

class Browser:
        def __init__(self):
                options = {
                        '''
                        'proxy': {
                                'http': 'http://127.0.0.1:7890',
                                'https': 'http://127.0.0.1:7890',
                                'no_proxy': 'localhost,127.0.0.1'
                                }
                        '''
                        }
                self.browser = webdriver.Chrome(seleniumwire_options=options);
                self.browser.request_interceptor = request_interceptor
            
        

