from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    DINGTALK_APP_KEY: str = ""
    DINGTALK_APP_SECRET: str = ""

    # HAI Gateway（用户自己的 token）
    ANTHROPIC_API_KEY: str = ""
    ANTHROPIC_BASE_URL: str = ""
    ANTHROPIC_DEFAULT_SONNET_MODEL: str = "claude-sonnet-4-6"

    class Config:
        env_file = ".env"
        extra = "ignore"


settings = Settings()
