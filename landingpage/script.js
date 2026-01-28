// Animated background with floating particles and gradient
const canvas = document.getElementById('bg-canvas');
const ctx = canvas.getContext('2d');

let width, height;
let particles = [];
let mouseX = 0;
let mouseY = 0;
let time = 0;

function resize() {
    width = canvas.width = window.innerWidth;
    height = canvas.height = window.innerHeight;
    initParticles();
}

function initParticles() {
    particles = [];
    const count = Math.floor((width * height) / 15000);
    for (let i = 0; i < count; i++) {
        particles.push({
            x: Math.random() * width,
            y: Math.random() * height,
            vx: (Math.random() - 0.5) * 0.3,
            vy: (Math.random() - 0.5) * 0.3,
            size: Math.random() * 2 + 0.5,
            opacity: Math.random() * 0.5 + 0.1
        });
    }
}

function drawGradient() {
    const gradient = ctx.createRadialGradient(
        width * 0.3, height * 0.3, 0,
        width * 0.3, height * 0.3, width * 0.8
    );
    gradient.addColorStop(0, 'rgba(99, 102, 241, 0.08)');
    gradient.addColorStop(0.5, 'rgba(139, 92, 246, 0.03)');
    gradient.addColorStop(1, 'transparent');

    ctx.fillStyle = gradient;
    ctx.fillRect(0, 0, width, height);

    // Second gradient
    const gradient2 = ctx.createRadialGradient(
        width * 0.8, height * 0.7, 0,
        width * 0.8, height * 0.7, width * 0.6
    );
    gradient2.addColorStop(0, 'rgba(236, 72, 153, 0.05)');
    gradient2.addColorStop(1, 'transparent');

    ctx.fillStyle = gradient2;
    ctx.fillRect(0, 0, width, height);
}

function drawParticles() {
    particles.forEach(p => {
        // Update position
        p.x += p.vx;
        p.y += p.vy;

        // Wrap around edges
        if (p.x < 0) p.x = width;
        if (p.x > width) p.x = 0;
        if (p.y < 0) p.y = height;
        if (p.y > height) p.y = 0;

        // Draw particle
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
        ctx.fillStyle = `rgba(255, 255, 255, ${p.opacity})`;
        ctx.fill();
    });

    // Draw connections between nearby particles
    for (let i = 0; i < particles.length; i++) {
        for (let j = i + 1; j < particles.length; j++) {
            const dx = particles[i].x - particles[j].x;
            const dy = particles[i].y - particles[j].y;
            const dist = Math.sqrt(dx * dx + dy * dy);

            if (dist < 120) {
                ctx.beginPath();
                ctx.moveTo(particles[i].x, particles[i].y);
                ctx.lineTo(particles[j].x, particles[j].y);
                ctx.strokeStyle = `rgba(255, 255, 255, ${0.03 * (1 - dist / 120)})`;
                ctx.stroke();
            }
        }
    }
}

function drawFloatingOrbs() {
    time += 0.005;

    // Animated orb 1
    const orb1X = width * 0.2 + Math.sin(time * 0.7) * 100;
    const orb1Y = height * 0.3 + Math.cos(time * 0.5) * 80;
    const gradient1 = ctx.createRadialGradient(orb1X, orb1Y, 0, orb1X, orb1Y, 200);
    gradient1.addColorStop(0, 'rgba(99, 102, 241, 0.15)');
    gradient1.addColorStop(1, 'transparent');
    ctx.fillStyle = gradient1;
    ctx.fillRect(0, 0, width, height);

    // Animated orb 2
    const orb2X = width * 0.75 + Math.cos(time * 0.6) * 120;
    const orb2Y = height * 0.6 + Math.sin(time * 0.4) * 100;
    const gradient2 = ctx.createRadialGradient(orb2X, orb2Y, 0, orb2X, orb2Y, 250);
    gradient2.addColorStop(0, 'rgba(168, 85, 247, 0.1)');
    gradient2.addColorStop(1, 'transparent');
    ctx.fillStyle = gradient2;
    ctx.fillRect(0, 0, width, height);

    // Animated orb 3
    const orb3X = width * 0.5 + Math.sin(time * 0.8) * 150;
    const orb3Y = height * 0.8 + Math.cos(time * 0.6) * 60;
    const gradient3 = ctx.createRadialGradient(orb3X, orb3Y, 0, orb3X, orb3Y, 180);
    gradient3.addColorStop(0, 'rgba(236, 72, 153, 0.08)');
    gradient3.addColorStop(1, 'transparent');
    ctx.fillStyle = gradient3;
    ctx.fillRect(0, 0, width, height);
}

function animate() {
    ctx.fillStyle = '#0a0a0f';
    ctx.fillRect(0, 0, width, height);

    drawGradient();
    drawFloatingOrbs();
    drawParticles();

    requestAnimationFrame(animate);
}

window.addEventListener('resize', resize);
window.addEventListener('mousemove', (e) => {
    mouseX = e.clientX;
    mouseY = e.clientY;
});

resize();
animate();
