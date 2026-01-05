import requests
from bs4 import BeautifulSoup
import os
import re
from urllib.parse import urlparse, urljoin
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
import logging

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class BizhiSpider:
    def __init__(self, base_url="https://www.bizhi99.com/2560x1600", download_dir="E:\\just-ads\\Pictures",
                 max_pages=21):
        """
        初始化爬虫

        Args:
            base_url: 目标网页URL
            download_dir: 图片下载目录
            max_pages: 最大翻页数限制
        """
        self.base_url = base_url
        self.download_dir = download_dir
        self.max_pages = max_pages
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
        })

        # 创建下载目录
        os.makedirs(self.download_dir, exist_ok=True)

        # URL验证模式
        self.url_pattern = re.compile(
            r'^https://pic\.dmjnb\.com/pic/[a-f0-9]{32}\?imageMogr2/thumbnail/x\d+/quality/\d+!$'
        )

    def fetch_page(self, url):
        """
        获取网页内容

        Args:
            url: 要访问的URL

        Returns:
            BeautifulSoup对象或None
        """
        try:
            logger.info(f"正在访问网页: {url}")
            response = self.session.get(url, timeout=30)
            response.raise_for_status()

            # 检测编码
            if response.encoding == 'ISO-8859-1':
                response.encoding = 'utf-8'

            soup = BeautifulSoup(response.text, 'html.parser')
            logger.info("网页获取成功")
            return soup
        except requests.RequestException as e:
            logger.error(f"获取网页失败 {url}: {e}")
            return None

    def extract_image_urls(self, soup):
        """
        提取图片URL

        Args:
            soup: BeautifulSoup对象

        Returns:
            图片URL列表
        """
        if not soup:
            return []

        image_urls = []

        # 查找所有class为item的元素下的img标签
        item_elements = soup.find_all(class_='item')
        logger.info(f"找到 {len(item_elements)} 个item元素")

        for item in item_elements:
            # 在item元素内查找img标签
            img_tags = item.find_all('img')
            for img in img_tags:
                # 优先使用data-original属性，如果没有则使用src
                src = img.get('data-original') or img.get('src')
                if src:
                    # 处理相对URL
                    full_url = urljoin(self.base_url, src)
                    image_urls.append(full_url)

        # 去重
        unique_urls = list(set(image_urls))
        logger.info(f"提取到 {len(unique_urls)} 个唯一图片URL")

        return unique_urls

    def validate_and_process_url(self, url):
        """
        验证URL格式并处理

        Args:
            url: 原始图片URL

        Returns:
            处理后的URL或None（如果URL无效）
        """
        # 验证URL格式
        if not self.url_pattern.match(url):
            logger.warning(f"URL格式不匹配: {url}")
            return None

        try:
            # 步骤4: 替换分辨率参数和质量参数
            # 替换 x380 为 x1600
            processed_url = re.sub(r'/x\d+/', '/x1600/', url)

            # 替换 90! 为 100!
            processed_url = re.sub(r'/\d+!$', '/100!', processed_url)

            logger.debug(f"URL处理完成: {url} -> {processed_url}")
            return processed_url
        except Exception as e:
            logger.error(f"URL处理失败 {url}: {e}")
            return None

    def download_image(self, url, index, total):
        """
        下载单张图片

        Args:
            url: 图片URL
            index: 图片索引
            total: 总图片数

        Returns:
            (成功状态, 文件名, 错误信息)
        """
        try:
            # 从URL提取文件名
            parsed_url = urlparse(url)
            path_parts = parsed_url.path.split('/')
            if len(path_parts) >= 3:
                # 使用哈希值作为文件名
                hash_part = path_parts[2].split('?')[0]
                filename = f"{hash_part}.jpg"
            else:
                # 使用索引作为文件名
                filename = f"image_{index:04d}.jpg"

            filepath = os.path.join(self.download_dir, filename)

            # 检查文件是否已存在
            if os.path.exists(filepath):
                logger.info(f"图片已存在，跳过: {filename}")
                return True, filename, None

            # 下载图片
            logger.info(f"正在下载图片 [{index}/{total}]: {filename}")
            response = self.session.get(url, timeout=60)
            response.raise_for_status()

            # 保存图片
            with open(filepath, 'wb') as f:
                f.write(response.content)

            file_size = os.path.getsize(filepath) / 1024  # KB
            logger.info(f"图片下载完成: {filename} ({file_size:.1f} KB)")

            return True, filename, None

        except requests.RequestException as e:
            error_msg = f"下载失败: {e}"
            logger.error(f"图片下载失败 {url}: {e}")
            return False, None, error_msg
        except Exception as e:
            error_msg = f"保存失败: {e}"
            logger.error(f"图片保存失败 {url}: {e}")
            return False, None, error_msg

    def crawl_all_pages(self):
        """
        爬取所有页面的图片URL

        Returns:
            所有页面的图片URL列表
        """
        all_image_urls = []
        current_url = self.base_url
        page_count = 0

        logger.info("开始爬取所有页面...")

        while current_url and page_count < self.max_pages:
            page_count += 1

            current_url = f'{self.base_url}/{page_count}.html'

            logger.info(f"正在处理第 {page_count} 页: {current_url}")

            # 获取当前页面
            soup = self.fetch_page(current_url)
            if not soup:
                logger.error(f"第 {page_count} 页获取失败，停止翻页")
                break

            # 提取当前页面的图片URL
            page_urls = self.extract_image_urls(soup)
            all_image_urls.extend(page_urls)
            logger.info(f"第 {page_count} 页提取到 {len(page_urls)} 个图片URL，累计 {len(all_image_urls)} 个")
            # 添加延迟，避免请求过于频繁
            time.sleep(1)

        # 去重
        unique_urls = list(set(all_image_urls))
        logger.info(f"总共爬取 {page_count} 页，提取到 {len(unique_urls)} 个唯一图片URL")

        return unique_urls

    def run(self, max_workers=5):
        """
        运行爬虫主流程

        Args:
            max_workers: 最大并发下载数
        """
        logger.info("=" * 50)
        logger.info("开始执行爬虫任务")
        logger.info(f"目标URL: {self.base_url}")
        logger.info(f"下载目录: {self.download_dir}")
        logger.info(f"最大翻页数: {self.max_pages}")
        logger.info("=" * 50)

        # 步骤1-2: 爬取所有页面的图片URL
        raw_urls = self.crawl_all_pages()
        if not raw_urls:
            logger.warning("未找到图片URL，任务终止")
            return

        # 步骤3-4: 验证和处理URL
        processed_urls = []
        for url in raw_urls:
            processed_url = self.validate_and_process_url(url)
            if processed_url:
                processed_urls.append(processed_url)

        logger.info(f"有效URL数量: {len(processed_urls)}")

        if not processed_urls:
            logger.warning("没有有效的图片URL，任务终止")
            return

        # 步骤5: 并发下载图片
        success_count = 0
        failed_count = 0

        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            # 提交所有下载任务
            future_to_url = {
                executor.submit(self.download_image, url, i + 1, len(processed_urls)): url
                for i, url in enumerate(processed_urls)
            }

            # 处理完成的任务
            for future in as_completed(future_to_url):
                url = future_to_url[future]
                try:
                    success, filename, error = future.result()
                    if success:
                        success_count += 1
                    else:
                        failed_count += 1
                        logger.error(f"下载失败: {url} - {error}")
                except Exception as e:
                    failed_count += 1
                    logger.error(f"任务执行异常 {url}: {e}")

                # 添加短暂延迟，避免请求过于频繁
                time.sleep(0.1)

        # 输出统计信息
        logger.info("=" * 50)
        logger.info("任务完成统计:")
        logger.info(f"总图片数: {len(processed_urls)}")
        logger.info(f"成功下载: {success_count}")
        logger.info(f"失败下载: {failed_count}")
        logger.info(f"下载目录: {self.download_dir}")
        logger.info("=" * 50)


def main():
    """
    主函数
    """
    # 配置参数
    base_url = "https://www.bizhi99.com/2560x1600"
    download_dir = "E:\\just-ads\\Pictures"
    max_pages = 20  # 最大翻页数，可根据需要调整

    # 创建爬虫实例并运行
    spider = BizhiSpider(base_url, download_dir, max_pages)
    spider.run(max_workers=10)


if __name__ == "__main__":
    main()
