import base64
import datetime
import os
from typing import Tuple

import json
from Crypto.Hash import SHA256
from Crypto.Signature.pkcs1_15 import _EMSA_PKCS1_V1_5_ENCODE
from Crypto.Util.number import ceil_div
from cryptography import x509
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.x509.oid import NameOID

# 常量定义
ONE_DAY = datetime.timedelta(days=1)
TEN_YEARS = datetime.timedelta(days=3650)
CA_COMMON_NAME = "JetProfile CA"
CERT_COMMON_NAME = "ADS"
KEY_SIZE = 4096
PUBLIC_EXPONENT = 65537


def generate_self_signed_certificate(
        cert_common_name: str = CERT_COMMON_NAME,
        key_size: int = KEY_SIZE,
        validity_days: int = 3650
) -> Tuple[rsa.RSAPrivateKey, x509.Certificate]:
    """
    生成自签名的CA证书

    Args:
        cert_common_name: 证书的通用名称
        key_size: RSA密钥大小
        validity_days: 证书有效期（天）

    Returns:
        私钥和证书的元组
    """
    print("\n=== 生成自签名CA证书 ===")
    today = datetime.datetime.today()
    not_valid_before = today - ONE_DAY
    not_valid_after = today + datetime.timedelta(days=validity_days)

    # 生成RSA密钥对
    private_key = rsa.generate_private_key(
        public_exponent=PUBLIC_EXPONENT,
        key_size=key_size,
        backend=default_backend()
    )
    public_key = private_key.public_key()

    # 构建证书
    builder = x509.CertificateBuilder()
    builder = builder.subject_name(x509.Name([
        x509.NameAttribute(NameOID.COMMON_NAME, cert_common_name),
    ]))
    builder = builder.issuer_name(x509.Name([
        x509.NameAttribute(NameOID.COMMON_NAME, 'JetProfile CA'),
    ]))
    builder = builder.not_valid_before(not_valid_before)
    builder = builder.not_valid_after(not_valid_after)
    builder = builder.serial_number(x509.random_serial_number())
    builder = builder.public_key(public_key)

    # 签名证书
    certificate = builder.sign(
        private_key=private_key,
        algorithm=hashes.SHA256(),
        backend=default_backend()
    )

    save_key_and_certificate(private_key, certificate)

    return private_key, certificate


def save_key_and_certificate(
        private_key: rsa.RSAPrivateKey,
        certificate: x509.Certificate,
        key_filename: str = "ca.key",
        cert_filename: str = "ca.crt"
) -> None:
    """
    保存私钥和证书到文件

    Args:
        private_key: RSA私钥
        certificate: X.509证书
        key_filename: 私钥文件名
        cert_filename: 证书文件名
    """
    # 序列化私钥
    private_bytes = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.TraditionalOpenSSL,
        encryption_algorithm=serialization.NoEncryption()
    )

    # 序列化证书
    public_bytes = certificate.public_bytes(
        encoding=serialization.Encoding.PEM
    )

    # 写入文件
    with open(key_filename, "wb") as f:
        f.write(private_bytes)
    with open(cert_filename, "wb") as f:
        f.write(public_bytes)

    print("✓ 证书已生成并保存到 ca.key 和 ca.crt")


def load_certificate_from_file() -> Tuple[rsa.RSAPrivateKey, x509.Certificate]:
    """
    从文件加载证书，支持PEM和DER格式
    Returns:
        X.509证书对象
    Raises:
        ValueError: 如果证书格式无效
    """

    print('\n======加载证书======')

    with open('ca.crt', "rb") as f:
        cert_data = f.read()

    with open('ca.key', "rb") as f:
        key_data = f.read()

    try:
        certificate = x509.load_pem_x509_certificate(cert_data, default_backend())
        private_key = serialization.load_pem_private_key(key_data, password=None)
        return private_key, certificate
    except Exception:
        try:
            certificate = x509.load_der_x509_certificate(cert_data, default_backend())
            private_key = serialization.load_der_private_key(key_data, password=None)
            return private_key, certificate
        except Exception as e:
            raise ValueError(f"无法加载证书文件: {e}")


def create_license_signature(license_data: dict, private_key: rsa.RSAPrivateKey) -> str:
    """
    创建许可证签名

    Args:
        license_data: 许可证数据
        private_key: 私钥
    Returns:
        完整的许可证字符串
    """
    try:
        license_id = license_data.get('licenseId')
        license_bytes = json.dumps(license_data).encode('utf-8')
        signature = private_key.sign(
            license_bytes,
            padding.PKCS1v15(),
            hashes.SHA1()
        )
        # Base64编码
        license_part_base64 = base64.b64encode(license_bytes).decode('utf-8')
        signature_base64 = base64.b64encode(signature).decode('utf-8')

        return f"{license_id}-{license_part_base64}-{signature_base64}"

    except Exception as e:
        print(f"创建许可证签名时出错: {e}")
        raise


def verify_license_signature(license_string: str, cert_base64: str) -> bool:
    """
    验证许可证签名

    Args:
        license_string: 许可证字符串
        cert_base64: Base64编码的证书（DER格式）

    Returns:
        签名是否有效
    """
    try:
        # 解析许可证字符串
        parts = license_string.split('-')
        if len(parts) < 3:
            raise ValueError("无效的许可证格式")

        license_part_base64 = parts[1]
        signature_base64 = parts[2]

        # 解码许可证数据
        license_data = base64.b64decode(license_part_base64).decode('utf-8')

        # 加载证书和公钥
        cert = x509.load_der_x509_certificate(base64.b64decode(cert_base64))
        public_key = cert.public_key()

        # 验证签名
        public_key.verify(
            base64.b64decode(signature_base64),
            license_data.encode('utf-8'),
            padding=padding.PKCS1v15(),
            algorithm=hashes.SHA1(),
        )

        return True

    except Exception as e:
        print(f"验证许可证签名时出错: {e}")
        return False


def generate_power_conf(sign, result):
    text = (
        "[Result]\n"
        f"EQUAL,{sign},{PUBLIC_EXPONENT},860106576952879101192782278876319243486072481962999610484027161162448933268423045647258145695082284265933019120714643752088997312766689988016808929265129401027490891810902278465065056686129972085119605237470899952751915070244375173428976413406363879128531449407795115913715863867259163957682164040613505040314747660800424242248055421184038777878268502955477482203711835548014501087778959157112423823275878824729132393281517778742463067583320091009916141454657614089600126948087954465055321987012989937065785013284988096504657892738536613208311013047138019418152103262155848541574327484510025594166239784429845180875774012229784878903603491426732347994359380330103328705981064044872334790365894924494923595382470094461546336020961505275530597716457288511366082299255537762891238136381924520749228412559219346777184174219999640906007205260040707839706131662149325151230558316068068139406816080119906833578907759960298749494098180107991752250725928647349597506532778539709852254478061194098069801549845163358315116260915270480057699929968468068015735162890213859113563672040630687357054902747438421559817252127187138838514773245413540030800888215961904267348727206110582505606182944023582459006406137831940959195566364811905585377246353"
        "->"
        f"{result}"
    )

    with open('power.conf', 'w', encoding='utf-8') as f:
        f.write(text)

    print(f"创建power.conf完成")


def main():
    is_cert_exists = os.path.exists('ca.key') and os.path.exists('ca.crt')
    if is_cert_exists:
        private_key, cert = load_certificate_from_file()
    else:
        private_key, cert = generate_self_signed_certificate()

    # 打印证书信息
    print(f"\n证书主题: {cert.subject}")
    print(f"证书颁发者: {cert.issuer}")
    print(f"证书有效期: {cert.not_valid_before_utc} 到 {cert.not_valid_after_utc}")
    print(f"证书序列号: {cert.serial_number} \n")

    cert_base64 = base64.b64encode(cert.public_bytes(serialization.Encoding.DER)).decode('utf-8')

    public_key = cert.public_key()

    # 计算签名值
    sign = int.from_bytes(cert.signature, byteorder="big")
    print(f"证书签名值: {sign}")

    # 计算TBS证书的哈希
    mod_bits = public_key.key_size
    digest_cert = SHA256.new(cert.tbs_certificate_bytes)

    # 使用PKCS#1 v1.5编码
    r = int.from_bytes(
        _EMSA_PKCS1_V1_5_ENCODE(digest_cert, ceil_div(mod_bits, 8)),
        byteorder='big',
        signed=False
    )
    print(f"计算得到的签名值: {r}")

    print(f"\n=== 生成power.conf ===")

    generate_power_conf(sign, r)

    print("\n=== 创建许可证签名 ===")
    date = (datetime.datetime.today() + datetime.timedelta(5 * 365)).strftime("%Y-%m-%d")

    license_data = {
        'licenseId': 'FV8EM46DQYC5AW9',
        'licenseeName': 'ADS',
        'licenseeType': 'PERSONAL',
        'assigneeName': 'ADS',
        'assigneeEmail': '',
        'licenseRestriction': '',
        'checkConcurrentUse': False,
        'products': [
            {"code": "PCWMP", "fallbackDate": date, "paidUpTo": date, "extended": True},
            {"code": "PRR", "fallbackDate": date, "paidUpTo": date, "extended": True},
            {"code": "PDB", "fallbackDate": date, "paidUpTo": date, "extended": True},
            {"code": "PSI", "fallbackDate": date, "paidUpTo": date, "extended": True},
            {"code": "II", "fallbackDate": date, "paidUpTo": date, "extended": False}
        ],
        'metadata': '0220240702PSAX000005X',
        'hash': '12345678/0-541816629',
        'gracePeriodDays': 7,
        'autoProlongated': False,
        'isAutoProlongated': False,
        'trial': False,
        'aiAllowed': True
    }
    license_string = f'{create_license_signature(license_data, private_key)}-{cert_base64}'
    print(f"✓ 许可证签名已创建")
    print(license_string)

    print("\n=== 验证许可证签名 ===")
    if verify_license_signature(license_string, cert_base64):
        print("✓ 许可证签名验证成功")
    else:
        print("✗ 许可证签名验证失败")


if __name__ == "__main__":
    main()
