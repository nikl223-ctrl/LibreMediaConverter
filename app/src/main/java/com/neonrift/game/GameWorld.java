package com.neonrift.game;

import java.util.ArrayList;
import java.util.Random;

public final class GameWorld {
    public static final float WIDTH = 3600f, HEIGHT = 2400f;
    public static final int CHASER = 0, STRAFER = 1, TANK = 2, BOSS = 3;
    public static final int HEAL = 0, OVERCLOCK = 1, SHIELD = 2;
    public static final int CYAN = 0xff47eaff, MAGENTA = 0xffff47bd, GOLD = 0xffffc965;
    public static final int RED = 0xffff5975, MINT = 0xff82ffd6;

    public static final class Enemy {
        public int kind;
        public float x, y, vx, vy, angle, hp, maxHp, radius, attack, age, flash;
        Enemy(int kind, float x, float y, float hp, float radius) {
            this.kind=kind; this.x=x; this.y=y; this.hp=hp; this.maxHp=hp;
            this.radius=radius; attack=1.1f;
        }
    }
    public static final class Bullet {
        public float x, y, vx, vy, life, radius, damage;
        public boolean friendly;
        public int color;
        Bullet(float x,float y,float vx,float vy,float life,float radius,float damage,boolean friendly,int color){
            this.x=x;this.y=y;this.vx=vx;this.vy=vy;this.life=life;
            this.radius=radius;this.damage=damage;this.friendly=friendly;this.color=color;
        }
    }
    public static final class Particle {
        public float x,y,vx,vy,life,maxLife,size;
        public int color;
        Particle(float x,float y,float vx,float vy,float life,float size,int color) {
            this.x=x;this.y=y;this.vx=vx;this.vy=vy;this.life=life;this.maxLife=life;this.size=size;this.color=color;
        }
    }
    public static final class Pickup {
        public float x,y,t;
        public int kind;
        Pickup(float x,float y,int kind){this.x=x;this.y=y;this.kind=kind;}
    }
    public final ArrayList<Enemy> enemies = new ArrayList<>();
    public final ArrayList<Bullet> bullets = new ArrayList<>();
    public final ArrayList<Particle> particles = new ArrayList<>();
    public final ArrayList<Pickup> pickups = new ArrayList<>();
    private final Random random = new Random();
    public float px,py,vx,vy,aim,hp,maxHp,dashCooldown,dashTime,invulnerable;
    public float overclock,shield,time,spawnTimer,wavePause,fireTimer,shake,comboTimer;
    public int wave,score,kills,combo,upgrades,pendingSpawns,spawned;
    public int soundShoot,soundHit,soundBoom,soundPickup,soundDash;
    public boolean dead, pendingBoss, bossSpawned;

    public GameWorld() { reset(); }
    public void reset(){
        enemies.clear();bullets.clear();particles.clear();pickups.clear();
        px=WIDTH*.5f;py=HEIGHT*.5f;vx=vy=0;aim=0;
        hp=maxHp=100;dashCooldown=dashTime=invulnerable=overclock=shield=0;
        time=0;spawnTimer=0;wavePause=1.7f;fireTimer=0;shake=0;comboTimer=0;
        wave=score=kills=combo=upgrades=pendingSpawns=spawned=0;
        dead=pendingBoss=bossSpawned=false;
        soundShoot=soundHit=soundBoom=soundPickup=soundDash=0;
    }
    public static float clamp(float v,float min,float max){return Math.max(min,Math.min(max,v));}
    private float rnd(float min,float max){return min+random.nextFloat()*(max-min);}
    public void update(float dt,float moveX,float moveY,float targetX,float targetY,boolean firing,boolean dashRequest) {
        if(dead)return;
        dt=clamp(dt,0f,.034f);
        time+=dt;dashCooldown=Math.max(0,dashCooldown-dt);
        dashTime=Math.max(0,dashTime-dt);invulnerable=Math.max(0,invulnerable-dt);
        overclock=Math.max(0,overclock-dt);shield=Math.max(0,shield-dt);
        shake=Math.max(0,shake-28*dt);
        fireTimer-=dt;comboTimer-=dt;
        if(comboTimer<=0)combo=0;
        float ml=(float)Math.hypot(moveX,moveY);
        if(ml>1){moveX/=ml;moveY/=ml;}
        if(targetX*targetX+targetY*targetY>.03f) aim=(float)Math.atan2(targetY,targetX);
        if(dashRequest && dashCooldown<=0 && wave>0){
            dashCooldown=3.2f;dashTime=.19f;invulnerable=Math.max(invulnerable,.28f);
            float dx=moveX,dy=moveY;
            if(dx*dx+dy*dy<.04f){dx=(float)Math.cos(aim);dy=(float)Math.sin(aim);}
            float dl=(float)Math.hypot(dx,dy);
            vx=dx/dl*1350;vy=dy/dl*1350;
            burst(px,py,CYAN,20,360);
            soundDash++;
        }
        if(dashTime<=0) {
            float speed=overclock>0?445:365;
            float smoothing=Math.min(1,dt*11f);
            vx+=(moveX*speed-vx)*smoothing;
            vy+=(moveY*speed-vy)*smoothing;
        } else if(random.nextFloat()<.95f) {
            spark(px-rnd(-15,15),py-rnd(-15,15),-vx*.17f+rnd(-50,50),-vy*.17f+rnd(-50,50),.3f,rnd(3,8),CYAN);
        }
        px=clamp(px+vx*dt,58,WIDTH-58);
        py=clamp(py+vy*dt,58,HEIGHT-58);
        if(firing && wave>0 && wavePause<=0 && fireTimer<=0){
            shootPlayer();
            fireTimer=overclock>0?.066f:Math.max(.074f,.148f-upgrades*.013f);
        }
        updateWaves(dt);
        updateEnemies(dt);
        updateBullets(dt);
        updatePickups(dt);
        updateParticles(dt);
    }
    private void updateWaves(float dt) {
        if(wavePause>0){
            wavePause-=dt;
            if(wavePause<=0)beginWave();
            return;
        }
        if(pendingSpawns>0) {
            spawnTimer-=dt;
            if(spawnTimer<=0 && enemies.size()<48) {
                if(pendingBoss && !bossSpawned){spawnEnemy(BOSS);bossSpawned=true;}
                else {
                    float n=random.nextFloat();
                    int kind=(wave>=3 && n<.17f)?TANK:(wave>=2 && n<.49f)?STRAFER:CHASER;
                    spawnEnemy(kind);
                }
                pendingSpawns--;
                spawned++;
                spawnTimer=Math.max(.18f,.88f-wave*.048f)*rnd(.75f,1.15f);
            }
        } else if(enemies.isEmpty()){
            wavePause=3.3f;
            bullets.removeIf(b->!b.friendly);
            hp=Math.min(maxHp,hp+8);
            if(wave%3==0) upgrades=Math.min(5,upgrades+1);
            combo=0;
        }
    }
    private void beginWave(){
        wave++;
        spawned=0;
        pendingBoss=wave%5==0;bossSpawned=false;
        pendingSpawns=(pendingBoss?12:8)+wave*3;
        spawnTimer=.35f;
        if(wave==1) { overclock=0;hp=maxHp; }
        burst(px,py,CYAN,24,280);
    }
    private void spawnEnemy(int kind) {
        float a=rnd(0,(float)Math.PI*2);
        float dist=rnd(800,1160);
        float x=clamp(px+(float)Math.cos(a)*dist,100,WIDTH-100);
        float y=clamp(py+(float)Math.sin(a)*dist,100,HEIGHT-100);
        float health=kind==CHASER?(2+wave*.28f):kind==STRAFER?(3.1f+wave*.38f):kind==TANK?(11+wave*.9f):(150+wave*9);
        float radius=kind==CHASER?23:kind==STRAFER?29:kind==TANK?42:104;
        Enemy e=new Enemy(kind,x,y,health,radius);
        e.attack=rnd(.7f,2.0f);
        enemies.add(e);
        burst(x,y,kind==BOSS?MAGENTA:RED,kind==BOSS?34:8,155);
    }
    private void shootPlayer(){
        float a=aim;
        int lanes=upgrades>=4?3:1;
        for(int i=0;i<lanes;i++) {
            float offset=lanes==1?0:(i-1)*.14f;
            float angle=a+offset;
            float ca=(float)Math.cos(angle),sa=(float)Math.sin(angle);
            bullets.add(new Bullet(px+ca*40,py+sa*40,ca*1350,sa*1350,.94f,7,
                    upgrades>=2?2.0f:1.6f,true,overclock>0?GOLD:CYAN));
        }
        spark(px+(float)Math.cos(a)*41,py+(float)Math.sin(a)*41,
                (float)Math.cos(a)*145,(float)Math.sin(a)*145,.15f,8,overclock>0?GOLD:CYAN);
        soundShoot++;
    }
    private void enemyFire(Enemy e,float a,int shots,float spread,float speed) {
        for(int i=0;i<shots;i++) {
            float f=shots==1?0:(i-(shots-1)/2f)*spread;
            float angle=a+f;
            float dx=(float)Math.cos(angle),dy=(float)Math.sin(angle);
            bullets.add(new Bullet(e.x+dx*e.radius,e.y+dy*e.radius,dx*speed,dy*speed,3.5f,
                    e.kind==BOSS?14:10,e.kind==BOSS?19:12,false,e.kind==BOSS?MAGENTA:RED));
        }
    }
    private void updateEnemies(float dt) {
        for(int i=enemies.size()-1;i>=0;i--){
            Enemy e=enemies.get(i);
            e.age+=dt;e.flash=Math.max(0,e.flash-dt);
            float dx=px-e.x,dy=py-e.y;
            float distance=Math.max(1f,(float)Math.hypot(dx,dy));
            float ux=dx/distance,uy=dy/distance;
            e.angle=(float)Math.atan2(dy,dx);
            float ax=ux,ay=uy,spd;
            if(e.kind==CHASER) spd=185+Math.min(80,wave*6);
            else if(e.kind==STRAFER){
                spd=215;
                if(distance<400){ax=-uy*.92f-ux*.35f;ay=ux*.92f-uy*.35f;}
                else if(distance<620){ax=uy*.9f+ux*.4f;ay=-ux*.9f+uy*.4f;}
                e.attack-=dt;
                if(e.attack<=0 && distance<980){
                    enemyFire(e,e.angle,1,0,510+wave*12);e.attack=rnd(1.2f,2.1f);
                }
            } else if(e.kind==TANK){
                spd=95;
                e.attack-=dt;
                if(e.attack<=0 && distance<800){
                    enemyFire(e,e.angle,3,.24f,410);
                    e.attack=rnd(2.2f,3.1f);
                }
            } else {
                spd=93;
                if(distance<480){ax=-ux;ay=-uy;}
                e.attack-=dt;
                if(e.attack<=0){
                    enemyFire(e,e.angle,7,.22f,480);
                    e.attack=1.25f;
                    shake=Math.max(shake,3);
                }
            }
            float turn=Math.min(1,dt*(e.kind==BOSS?2.3f:4f));
            e.vx+=(ax*spd-e.vx)*turn;e.vy+=(ay*spd-e.vy)*turn;
            e.x=clamp(e.x+e.vx*dt,65,WIDTH-65);
            e.y=clamp(e.y+e.vy*dt,65,HEIGHT-65);
            float overlap=e.radius+29;
            float cd=(float)Math.hypot(px-e.x,py-e.y);
            if(cd<overlap && invulnerable<=0) {
                takeDamage(e.kind==BOSS?25:e.kind==TANK?17:11);
                float pushX=(px-e.x)/Math.max(1,cd),pushY=(py-e.y)/Math.max(1,cd);
                vx+=pushX*460;vy+=pushY*460;
            }
        }
    }
    private void updateBullets(float dt) {
        for(int i=bullets.size()-1;i>=0;i--){
            Bullet b=bullets.get(i);
            b.life-=dt;b.x+=b.vx*dt;b.y+=b.vy*dt;
            boolean remove=b.life<=0||b.x<0||b.y<0||b.x>WIDTH||b.y>HEIGHT;
            if(!remove && b.friendly){
                for(int j=enemies.size()-1;j>=0;j--){
                    Enemy e=enemies.get(j);
                    float dx=b.x-e.x,dy=b.y-e.y,r=e.radius+b.radius;
                    if(dx*dx+dy*dy<r*r) {
                        e.hp-=b.damage;e.flash=.10f;remove=true;
                        spark(b.x,b.y,-b.vx*.14f+rnd(-85,85),-b.vy*.14f+rnd(-85,85),.25f,5,GOLD);
                        if(e.hp<=0) {
                            killEnemy(e);enemies.remove(j);
                        }
                        break;
                    }
                }
            } else if(!remove && !b.friendly && invulnerable<=0){
                float dx=b.x-px,dy=b.y-py,r=b.radius+26;
                if(dx*dx+dy*dy<r*r){
                    takeDamage(b.damage);remove=true;
                }
            }
            if(remove)bullets.remove(i);
        }
    }
    private void killEnemy(Enemy e) {
        kills++;combo++;comboTimer=3.8f;
        score+=(e.kind==BOSS?3000:e.kind==TANK?300:e.kind==STRAFER?180:100)*Math.min(5,1+combo/10);
        int color=e.kind==BOSS?MAGENTA:e.kind==TANK?GOLD:RED;
        burst(e.x,e.y,color,e.kind==BOSS?65:e.kind==TANK?24:12,e.kind==BOSS?530:255);
        soundBoom++;
        shake=Math.max(shake,e.kind==BOSS?21:4);
        if(e.kind==BOSS) {
            pickups.add(new Pickup(e.x-80,e.y,HEAL));
            pickups.add(new Pickup(e.x+80,e.y,OVERCLOCK));
            pickups.add(new Pickup(e.x,e.y+90,SHIELD));
        } else {
            float chance=random.nextFloat();
            if(chance<.075f)pickups.add(new Pickup(e.x,e.y,HEAL));
            else if(chance<.14f)pickups.add(new Pickup(e.x,e.y,OVERCLOCK));
            else if(chance<.19f)pickups.add(new Pickup(e.x,e.y,SHIELD));
        }
    }
    private void takeDamage(float amount) {
        if(shield>0){shield=0;invulnerable=.28f;burst(px,py,MINT,17,290);}
        else {hp-=amount;invulnerable=.85f;soundHit++;shake=Math.max(shake,13);burst(px,py,RED,14,270);}
        combo=0;
        if(hp<=0){hp=0;dead=true;shake=30;burst(px,py,CYAN,65,570);soundBoom++;}
    }
    private void updatePickups(float dt){
        for(int i=pickups.size()-1;i>=0;i--) {
            Pickup p=pickups.get(i);p.t+=dt;
            float dx=px-p.x,dy=py-p.y,d=(float)Math.hypot(dx,dy);
            if(d<185 && d>1){
                p.x+=dx/d*dt*430;p.y+=dy/d*dt*430;
            }
            if(d<55){
                if(p.kind==HEAL)hp=Math.min(maxHp,hp+25);
                if(p.kind==OVERCLOCK)overclock=11f;
                if(p.kind==SHIELD)shield=16f;
                pickups.remove(i);soundPickup++;score+=75;
                burst(p.x,p.y,p.kind==HEAL?MINT:p.kind==OVERCLOCK?GOLD:CYAN,18,190);
            } else if(p.t>19f)pickups.remove(i);
        }
    }
    private void updateParticles(float dt){
        for(int i=particles.size()-1;i>=0;i--){
            Particle p=particles.get(i);
            p.life-=dt;
            if(p.life<=0){particles.remove(i);continue;}
            p.x+=p.vx*dt;p.y+=p.vy*dt;
            p.vx*=Math.max(0,1-dt*2.2f);
            p.vy*=Math.max(0,1-dt*2.2f);
        }
        if(particles.size()>420)particles.subList(0,particles.size()-420).clear();
    }
    private void burst(float x,float y,int color,int count,float speed){
        for(int i=0;i<count;i++){
            float a=rnd(0,6.2831853f),s=rnd(speed*.14f,speed),life=rnd(.2f,.74f);
            spark(x,y,(float)Math.cos(a)*s,(float)Math.sin(a)*s,life,rnd(2,8),color);
        }
    }
    private void spark(float x,float y,float vx,float vy,float life,float size,int color){
        if(particles.size()<450)particles.add(new Particle(x,y,vx,vy,life,size,color));
    }
    public float waveProgress(){
        int total=(wave%5==0?12:8)+wave*3;
        return total==0?0:clamp(1-(pendingSpawns+enemies.size())/(float)total,0,1);
    }
    public float bossHealth(){
        for(Enemy e:enemies)if(e.kind==BOSS)return e.hp/e.maxHp;
        return -1;
    }
}
